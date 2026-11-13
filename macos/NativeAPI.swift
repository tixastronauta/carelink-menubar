import Foundation

final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class NativeAPI {
    private let session: URLSession
    private let vault: TokenStorage
    /// Field paths and types of the last display payload (no values), for diagnostics.
    private(set) var lastShape: [String]?
    func clearShape() { lastShape = nil }
    init(vault: TokenStorage, session: URLSession? = nil) {
        self.vault = vault
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 30
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.urlCredentialStorage = nil
            self.session = URLSession(configuration:configuration, delegate:NoRedirects(), delegateQueue:nil)
        }
    }
    private func request(_ url: URL, method: String = "GET", body: [String:Any]? = nil,
                         token: String? = nil, form: Bool = false) async throws -> Any {
        try Task.checkCancellation()
        guard NetworkPolicy.allows(method:method, url:url, body:body) else { throw CareLinkError.configuration }
        var request = URLRequest(url:url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField:"Accept")
        request.setValue("Dalvik/2.1.0 (Linux; U; Android 10; Nexus 5X Build/QQ3A.200805.001)", forHTTPHeaderField:"User-Agent")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField:"Authorization") }
        if let body {
            if form {
                let allowed = CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
                request.httpBody = body.keys.sorted().map { key in
                    let value = body[key] as? String ?? ""
                    return key.addingPercentEncoding(withAllowedCharacters:allowed)! + "=" + value.addingPercentEncoding(withAllowedCharacters:allowed)!
                }.joined(separator:"&").data(using:.utf8)
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField:"Content-Type")
            } else {
                request.httpBody = try JSONSerialization.data(withJSONObject:body)
                request.setValue("application/json", forHTTPHeaderField:"Content-Type")
            }
        }
        let (data,response) = try await session.data(for:request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw CareLinkError.network }
        if Diagnostics.isEnabled {
            Diagnostics.record(method:method, url:url, status:response.statusCode, request:body,
                               response:try? JSONSerialization.jsonObject(with:data))
        }
        if url == Endpoints.display, response.statusCode == 206,
           ((try? JSONSerialization.jsonObject(with:data)) as? [String:Any])?["message"] as? String == "Upgrade application" {
            throw CareLinkError.outdatedClient
        }
        if (url == Endpoints.token && response.statusCode == 400) || response.statusCode == 401 || response.statusCode == 403 { throw CareLinkError.authentication }
        guard response.statusCode == 200, data.count < 10_000_000 else { throw CareLinkError.network }
        do { return try JSONSerialization.jsonObject(with:data) }
        catch { throw CareLinkError.schema }
    }
    func metadata() async throws -> OAuthMetadata {
        guard let object = try await request(Endpoints.sso) as? [String:Any] else { throw CareLinkError.configuration }
        return try OAuthMetadata(object)
    }
    func exchange(code: String, verifier: String, metadata: OAuthMetadata) async throws -> Tokens {
        let body = ["grant_type":"authorization_code","client_id":metadata.clientID,"code":code,
                    "redirect_uri":metadata.redirect.absoluteString,"code_verifier":verifier]
        guard let object = try await request(Endpoints.token,method:"POST",body:body,form:true) as? [String:Any] else { throw CareLinkError.authentication }
        return try Tokens.response(object,clientID:metadata.clientID)
    }
    private func renew(_ tokens: Tokens) async throws -> Tokens {
        guard let object = try await request(Endpoints.token,method:"POST",body:["grant_type":"refresh_token",
            "client_id":tokens.clientID,"refresh_token":tokens.refreshToken],form:true) as? [String:Any] else { throw CareLinkError.authentication }
        let fresh = try Tokens.response(object,clientID:tokens.clientID,previous:tokens)
        try Task.checkCancellation()
        try vault.save(fresh)
        return fresh
    }
    func fetch(allowRenewal: Bool = true) async throws -> Snapshot {
        guard var tokens = try vault.load() else { throw CareLinkError.authentication }
        var renewed = false
        if tokens.needsRefresh {
            guard allowRenewal else { throw CareLinkError.authentication }
            tokens = try await renew(tokens); renewed = true
        }
        do { return try await read(tokens) }
        catch CareLinkError.authentication where !renewed && allowRenewal {
            tokens = try await renew(tokens)
            return try await read(tokens)
        }
    }
    private func read(_ tokens: Tokens) async throws -> Snapshot {
        guard let details = tokens.claims?["token_details"] as? [String:Any],
              let country = details["country"] as? String,
              let username = details["preferred_username"] as? String else { throw CareLinkError.authentication }
        guard let discovery = try await request(Endpoints.discovery) as? [String:Any],
              let countries = discovery["supportedCountries"] as? [[String:Any]],
              countries.contains(where: { ($0[country.uppercased()] as? [String:Any])?["region"] as? String == "EU" }),
              let regions = discovery["CP"] as? [[String:Any]],
              let region = regions.first(where: { $0["region"] as? String == "EU" }),
              region["baseUrlCareLink"] as? String == "https://carelink.minimed.eu/api/carepartner/v2",
              region["baseUrlCumulus"] as? String == "https://clcloud.minimed.eu/connect/carepartner/v13" else { throw CareLinkError.configuration }
        guard let user = try await request(Endpoints.user,token:tokens.accessToken) as? [String:Any],
              let role = user["role"] as? String else { throw CareLinkError.schema }
        var body: [String:Any] = ["username":username,"role":"patient"]
        if ["CARE_PARTNER","CARE_PARTNER_OUS"].contains(role) {
            guard let patients = try await request(Endpoints.patients,token:tokens.accessToken) as? [[String:Any]],
                  patients.count == 1, let patient = patients.first?["username"] as? String else { throw CareLinkError.multiplePatients }
            body["role"] = "carepartner"; body["patientId"] = patient
            body["appVersion"] = ClientIdentity.appVersion; body["os"] = ClientIdentity.os
        } else if !["PATIENT","PATIENT_OUS"].contains(role) { throw CareLinkError.configuration }
        guard let raw = try await request(Endpoints.display,method:"POST",body:body,token:tokens.accessToken) as? [String:Any] else { throw CareLinkError.schema }
        lastShape = Diagnostics.shape(raw)
        return try NativeParser.snapshot(raw)
    }
}
