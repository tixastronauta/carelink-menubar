import Foundation

final class MemoryVault: TokenStorage {
    var tokens: Tokens?
    var saves = 0
    init(_ tokens: Tokens?) { self.tokens = tokens }
    func load() throws -> Tokens? { tokens }
    func save(_ tokens: Tokens) throws { try Task.checkCancellation(); self.tokens = tokens; saves += 1 }
    func clear() throws { tokens = nil }
}

final class MockCareLink: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Any))!
    static var delay: TimeInterval = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.delay > 0 { Thread.sleep(forTimeInterval:Self.delay) }
        let (status, object) = Self.handler(request)
        let response = HTTPURLResponse(url:request.url!, statusCode:status, httpVersion:nil, headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:object))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct NativeIntegrationChecks {
    static func jwt(expiry: Double, country: String = "PT") -> String {
        let claims: [String:Any] = ["exp":expiry,"token_details":["country":country,"preferred_username":"synthetic"]]
        return "synthetic." + OAuthFlow.base64URL(try! JSONSerialization.data(withJSONObject:claims)) + ".synthetic"
    }
    @MainActor static func main() async throws {
        L10n.choice = .portuguese
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockCareLink.self]
        let session = URLSession(configuration:config)
        let initial = Tokens(accessToken:jwt(expiry:0),refreshToken:"old",clientID:"synthetic")
        let vault = MemoryVault(initial)
        var requests: [String] = []
        var failUser = false
        var role = "PATIENT"
        var displayBodies: [[String:Any]] = []
        var outdated = false
        var country = "PT"
        var hosts: [String] = []
        MockCareLink.handler = { request in
            let url = request.url!
            requests.append(url.path); hosts.append(url.host ?? "")
            let endpoints = Endpoints.all.first { [$0.token,$0.user,$0.patients,$0.display].contains(url) }
            switch url as URL? {
            case endpoints?.token: return (200,["access_token":jwt(expiry:Date().timeIntervalSince1970+7200,country:country),"refresh_token":"rotated"])
            case Endpoints.discovery: return (200,["supportedCountries":[["PT":["region":"EU"]],["US":["region":"US"]]], "CP":[
                ["region":"US","baseUrlCareLink":"https://carelink.minimed.com/api/carepartner/v2","baseUrlCumulus":"https://clcloud.minimed.com/connect/carepartner/v13"],
                ["region":"EU","baseUrlCareLink":"https://carelink.minimed.eu/api/carepartner/v2","baseUrlCumulus":"https://clcloud.minimed.eu/connect/carepartner/v13"]]])
            case endpoints?.user: return failUser ? (500,[:]) : (200,["role":role])
            case endpoints?.patients: return (200,[["username":"synthetic-patient"]])
            case endpoints?.display:
                let body = request.httpBodyStream.map { stream -> [String:Any] in
                    stream.open(); defer { stream.close() }
                    var data = Data(); var buffer = [UInt8](repeating:0,count:4096)
                    while stream.hasBytesAvailable { let n = stream.read(&buffer,maxLength:buffer.count); if n <= 0 { break }; data.append(buffer,count:n) }
                    return (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
                } ?? [:]
                displayBodies.append(body)
                if outdated { return (206,["message":"Upgrade application"]) }
                return (200,["patientData":["bgUnits":"MGDL","clientTimeZoneName":"Europe/Lisbon","lastSG":["sg":123,"timestamp":"2026-10-28T12:00:00"],"activeInsulin":["amount":0],"sgs":[]]])
            default: preconditionFailure("Unexpected URL")
            }
        }
        let api = NativeAPI(vault:vault,session:session)
        let snapshot = try await api.fetch()
        precondition(snapshot.glucose == 123 && snapshot.activeInsulin == 0)
        precondition(vault.tokens?.refreshToken == "rotated" && vault.saves == 1)
        precondition(requests.count == 4)
        vault.tokens = initial; failUser = true
        do { _ = try await api.fetch(); preconditionFailure() } catch {}
        precondition(vault.tokens?.refreshToken == "rotated", "Rotated token must survive a later read failure")
        failUser = false; displayBodies = []
        let patientRead = try await api.fetch(); precondition(patientRead.glucose == 123)
        precondition(displayBodies.last?["role"] as? String == "patient" && displayBodies.last?["appVersion"] == nil,
                     "Patient read must stay unchanged")
        role = "CARE_PARTNER_OUS"
        let partnerRead = try await api.fetch(); precondition(partnerRead.glucose == 123)
        let partner = displayBodies.last ?? [:]
        precondition(partner["role"] as? String == "carepartner" && partner["patientId"] as? String == "synthetic-patient"
                     && partner["appVersion"] as? String == ClientIdentity.appVersion && partner["os"] as? String == ClientIdentity.os,
                     "Care partner read must declare the client version")
        outdated = true
        do { _ = try await api.fetch(); preconditionFailure() }
        catch CareLinkError.outdatedClient {} catch { preconditionFailure("206 Upgrade application must map to outdatedClient") }
        outdated = false; role = "PATIENT"
        // US session: every authenticated request stays on the US hosts.
        country = "US"; hosts = []
        vault.tokens = Tokens(accessToken:jwt(expiry:0,country:"US"),refreshToken:"old",clientID:"synthetic",region:.us)
        let usRead = try await api.fetch(); precondition(usRead.glucose == 123)
        precondition(vault.tokens?.region == .us, "Renewal must keep the US region")
        precondition(hosts == ["carelink-login.minimed.com","clcloud.minimed.eu","carelink.minimed.com","clcloud.minimed.com"],
                     "US reads use US hosts (discovery is shared)")
        role = "CARE_PARTNER"
        let usPartner = try await api.fetch(); precondition(usPartner.glucose == 123 && displayBodies.last?["role"] as? String == "carepartner")
        role = "PATIENT"
        // An EU session whose account country belongs to the US region is rejected, and vice versa.
        vault.tokens = Tokens(accessToken:jwt(expiry:Date().timeIntervalSince1970+7200,country:"US"),refreshToken:"r",clientID:"synthetic")
        do { _ = try await api.fetch(); preconditionFailure() } catch CareLinkError.configuration {} catch { preconditionFailure("Region mismatch must be a configuration error") }
        vault.tokens = Tokens(accessToken:jwt(expiry:Date().timeIntervalSince1970+7200,country:"PT"),refreshToken:"r",clientID:"synthetic",region:.us)
        do { _ = try await api.fetch(); preconditionFailure() } catch CareLinkError.configuration {} catch { preconditionFailure("Region mismatch must be a configuration error") }
        country = "PT"
        failUser = false; vault.tokens = initial; MockCareLink.delay = 0.2
        let store = CareLinkStore(vault:vault,session:session)
        store.start()
        try await Task.sleep(nanoseconds:30_000_000)
        store.logout()
        try await Task.sleep(nanoseconds:400_000_000)
        precondition(vault.tokens == nil && !store.isSignedIn && !store.isRefreshing && store.snapshot == nil)
        store.tick()
        precondition(!store.isRefreshing, "Logged-out timer must not fetch")
        store.stop(); session.invalidateAndCancel()
        print("PASS: native API read (EU and US), region mismatch, care partner read with client version, outdated-client error, refresh rotation, persistence after API failure, cancellation/logout race and logged-out timer")
    }
}
