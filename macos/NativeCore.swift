import Foundation
import CryptoKit
import Security

// Protocol compatibility derived from ondrej1024/carelink-python-client (AGPL-3.0).
enum CareLinkError: Error {
    case authentication, configuration, schema, network, multiplePatients, keychain, cancelled, outdatedClient
    var message: String {
        switch self {
        case .authentication: return tr("A sessão expirou ou não foi aceite. Volta a entrar no CareLink.")
        case .configuration: return tr("A configuração europeia do CareLink mudou ou a conta pertence a outra região.")
        case .schema: return tr("O CareLink devolveu um formato de dados não reconhecido.")
        case .network: return tr("Não foi possível contactar o CareLink. Verifica a ligação e tenta novamente.")
        case .multiplePatients: return tr("Esta versão precisa de uma conta com exatamente um paciente associado.")
        case .keychain: return tr("Não foi possível aceder ao Porta-chaves. Autoriza o acesso à sessão desta app.")
        case .cancelled: return tr("Início de sessão cancelado.")
        case .outdatedClient: return tr("O CareLink deixou de aceitar a versão de cliente que esta app indica. É preciso atualizar a app.")
        }
    }
}

enum Endpoints {
    static let discovery = URL(string:"https://clcloud.minimed.eu/connect/carepartner/v13/discover/android/3.6")!
    static let sso = URL(string:"https://carelink.minimed.eu/configs/v1/carepartner_auth0_ous_sso_config_v1.json")!
    static let user = URL(string:"https://carelink.minimed.eu/api/carepartner/v2/users/me")!
    static let patients = URL(string:"https://carelink.minimed.eu/api/carepartner/v2/links/patients")!
    static let display = URL(string:"https://clcloud.minimed.eu/connect/carepartner/v13/display/message")!
    static let token = URL(string:"https://carelink-login.minimed.eu/oauth/token")!
    static let authorize = URL(string:"https://carelink-login.minimed.eu/authorize")!
}

/// Client version declared in the care partner display/message body. Since October 2026 the server
/// answers HTTP 206 {"message":"Upgrade application"} to care partner reads without it (community
/// reports: below 3.7 is rejected). Patient reads work without it and are left unchanged.
enum ClientIdentity {
    static let appVersion = "3.8"
    static let os = "android"
}

enum NetworkPolicy {
    static func allows(method: String, url: URL, body: [String: Any]?) -> Bool {
        if method == "GET" { return [Endpoints.discovery, Endpoints.sso, Endpoints.user, Endpoints.patients].contains(url) }
        guard method == "POST", let body else { return false }
        if url == Endpoints.display {
            return Set(body.keys).isSubset(of:["username","role","patientId","appVersion","os"])
                && body["username"] is String && ["patient","carepartner"].contains(body["role"] as? String ?? "")
                && (body["appVersion"] == nil || body["appVersion"] as? String == ClientIdentity.appVersion)
                && (body["os"] == nil || body["os"] as? String == ClientIdentity.os)
        }
        if url == Endpoints.token {
            return Set(body.keys).isSubset(of:["grant_type","client_id","code","redirect_uri","code_verifier","refresh_token"])
                && ["authorization_code","refresh_token"].contains(body["grant_type"] as? String ?? "")
        }
        return false
    }
}

struct Tokens: Codable {
    var accessToken: String
    var refreshToken: String
    var clientID: String
    static func response(_ object: [String: Any], clientID: String, previous: Tokens? = nil) throws -> Tokens {
        guard let access = object["access_token"] as? String, !access.isEmpty,
              let refresh = object["refresh_token"] as? String ?? previous?.refreshToken, !refresh.isEmpty else { throw CareLinkError.authentication }
        return Tokens(accessToken:access, refreshToken:refresh, clientID:clientID)
    }
    var claims: [String: Any]? {
        let parts = accessToken.split(separator:".")
        guard parts.count == 3 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of:"-", with:"+").replacingOccurrences(of:"_", with:"/")
        encoded += String(repeating:"=", count:(4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded:encoded) else { return nil }
        return (try? JSONSerialization.jsonObject(with:data)) as? [String: Any]
    }
    /// Account shown in Settings: email claim if present, else the CareLink username.
    var accountName: String? {
        let details = claims?["token_details"] as? [String: Any]
        for value in [claims?["email"], details?["email"], details?["preferred_username"], claims?["preferred_username"]] {
            if let text = value as? String, !text.isEmpty { return text }
        }
        return nil
    }
    var needsRefresh: Bool {
        guard let expiry = claims?["exp"] as? Double else { return true }
        return expiry - Date().timeIntervalSince1970 < 600
    }
}

struct OAuthMetadata {
    let clientID: String
    let scope: String
    let audience: String
    let redirect: URL
    init(_ object: [String: Any]) throws {
        guard let server = object["server"] as? [String:Any],
              server["hostname"] as? String == "carelink-login.minimed.eu",
              server["port"] as? Int == 443,
              server["prefix"] as? String == "",
              let endpoints = object["system_endpoints"] as? [String:Any],
              endpoints["authorization_endpoint_path"] as? String == "/authorize",
              endpoints["token_endpoint_path"] as? String == "/oauth/token",
              let client = object["client"] as? [String:Any],
              let id = client["client_id"] as? String, !id.isEmpty,
              let scope = client["scope"] as? String,
              let audience = client["audience"] as? String,
              let redirectString = client["redirect_uri"] as? String,
              let redirect = URL(string:redirectString),
              redirect.scheme == "com.medtronic.carepartner", redirect.path == "/sso",
              redirect.host == nil, redirect.query == nil, redirect.fragment == nil else { throw CareLinkError.configuration }
        self.clientID = id; self.scope = scope; self.audience = audience; self.redirect = redirect
    }
}

enum OAuthFlow {
    static func random() throws -> String {
        var bytes = [UInt8](repeating:0, count:32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CareLinkError.authentication }
        return base64URL(Data(bytes))
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of:"+", with:"-").replacingOccurrences(of:"/", with:"_").replacingOccurrences(of:"=", with:"")
    }
    static func challenge(_ verifier: String) -> String { base64URL(Data(SHA256.hash(data:Data(verifier.utf8)))) }
    static func authorizationURL(metadata: OAuthMetadata, state: String, verifier: String) -> URL {
        var url = URLComponents(url:Endpoints.authorize, resolvingAgainstBaseURL:false)!
        url.queryItems = ["client_id":metadata.clientID, "response_type":"code", "scope":metadata.scope,
            "redirect_uri":metadata.redirect.absoluteString, "audience":metadata.audience, "state":state,
            "code_challenge":challenge(verifier), "code_challenge_method":"S256"].map { URLQueryItem(name:$0.key, value:$0.value) }
        return url.url!
    }
    static func code(from callback: URL, redirect: URL, state: String) throws -> String {
        guard callback.scheme == redirect.scheme, callback.host == redirect.host,
              callback.path == redirect.path, callback.fragment == nil,
              let items = URLComponents(url:callback, resolvingAgainstBaseURL:false)?.queryItems else { throw CareLinkError.authentication }
        let states = items.filter { $0.name == "state" }
        let codes = items.filter { $0.name == "code" }
        guard states.count == 1, states[0].value == state, codes.count == 1,
              let code = codes[0].value, !code.isEmpty,
              !items.contains(where: { $0.name == "error" }) else { throw CareLinkError.authentication }
        return code
    }
}

enum NativeParser {
    static func number(_ value: Any?, positive: Bool = false) -> Double? {
        guard let value, let n = value as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let result = n.doubleValue
        return result.isFinite && (positive ? result > 0 : result >= 0) ? result : nil
    }
    static func flag(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }
    static func timestamp(_ value: Any?, zone: String?) -> String? {
        guard let value = value as? String else { return nil }
        let output = ISO8601DateFormatter()
        if let date = Snapshot.parseDate(value) { return output.string(from:date) }
        guard let zone, let tz = TimeZone(identifier:zone) else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier:"en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT:0)
        format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        format.isLenient = false
        guard let localAsUTC = format.date(from:value), format.string(from:localAsUTC) == value else { return nil }
        // Check neighboring offsets: exactly one UTC instant must round-trip to this wall time.
        let offsets = Set([-86400.0, 0, 86400].map { tz.secondsFromGMT(for:localAsUTC.addingTimeInterval($0)) })
        format.timeZone = tz
        let candidates = offsets.map { localAsUTC.addingTimeInterval(-Double($0)) }.filter { format.string(from:$0) == value }
        guard Set(candidates).count == 1, let date = candidates.first else { return nil }
        return output.string(from:date)
    }
    static func snapshot(_ raw: [String:Any]) throws -> Snapshot {
        let data = raw["patientData"] as? [String:Any] ?? raw
        guard ["lastSG","sgs","activeInsulin"].contains(where:{ data[$0] != nil }) else { throw CareLinkError.schema }
        let zone = data["clientTimeZoneName"] as? String
        let last = data["lastSG"] as? [String:Any] ?? [:]
        let active = data["activeInsulin"] as? [String:Any] ?? [:]
        let unit = ["MGDL":"mg/dL","MMOLL":"mmol/L","mg/dL":"mg/dL","mmol/L":"mmol/L"][data["bgUnits"] as? String ?? ""]
        let time = timestamp(last["timestamp"],zone:zone) ?? timestamp(last["datetime"],zone:zone)
            ?? timestamp(data["lastSGDateTime"],zone:zone) ?? timestamp(data["sLastSensorTime"],zone:zone)
            ?? timestamp(data["lastSensorTSAsString"],zone:zone)
        var points: [String:Double] = [:]
        for item in data["sgs"] as? [[String:Any]] ?? [] {
            if let time = timestamp(item["timestamp"],zone:zone) ?? timestamp(item["datetime"],zone:zone),
               let value = number(item["sg"],positive:true) { points[time] = value }
        }
        // Third-party clients treat CareLink `sg` as mg/dL even for MMOLL accounts (unconfirmed:
        // no mmol payload seen). Values above 35 cannot be mmol/L, so convert them for display.
        let lastValue = number(last["sg"],positive:true)
        let sgInMgdl = unit == "mmol/L" && (([lastValue].compactMap { $0 } + Array(points.values)).max() ?? 0) > 35
        func glucose(_ value: Double) -> Double { sgInMgdl ? value / GlucoseRange.mmolFactor : value }
        points = points.mapValues(glucose)
        let algorithm = data["therapyAlgorithmState"] as? [String:Any] ?? [:]
        var pumpLimits: ClosedRange<Double>?
        if let limit = (data["limits"] as? [[String:Any]])?.first,
           var low = number(limit["lowLimit"], positive:true), var high = number(limit["highLimit"], positive:true) {
            // Limits may be mmol/L on MMOLL accounts; values above 35 are already mg/dL.
            if unit == "mmol/L", high <= 35 { low *= GlucoseRange.mmolFactor; high *= GlucoseRange.mmolFactor }
            if low >= 40, high <= 400, low < high { pumpLimits = low...high }
        }
        var markers: [TherapyMarker] = []
        for item in data["markers"] as? [[String:Any]] ?? [] {
            guard let stamp = timestamp(item["timestamp"],zone:zone), let date = Snapshot.parseDate(stamp) else { continue }
            let values = (item["data"] as? [String:Any])?["dataValues"] as? [String:Any] ?? [:]
            switch item["type"] as? String {
            case "INSULIN":
                guard values["completed"] as? Bool != false,
                      let amount = Double(values["deliveredFastAmount"] as? String ?? ""), amount > 0, amount <= 50 else { continue }
                let auto = values["activationType"] as? String == "AUTOCORRECTION"
                markers.append(TherapyMarker(kind: auto ? .autoCorrection : .bolus, date: date, amount: amount))
            case "MEAL":
                guard let grams = number(values["amount"], positive: true), grams <= 500 else { continue }
                markers.append(TherapyMarker(kind: .meal, date: date, amount: grams))
            default: continue  // AUTO_BASAL_DELIVERY and others are not plotted
            }
        }
        // Device status: names confirmed on a real Flex payload (2026-11-07); out-of-range values are dropped.
        let battery = (number(data["pumpBatteryLevelPercent"]) ?? number(data["medicalDeviceBatteryLevelPercent"]))
            .flatMap { $0 <= 100 ? $0 : nil }
        let sensor = number(data["sensorDurationHours"]).flatMap { $0 <= 240 ? $0 : nil }
        let reservoir = number(data["reservoirRemainingUnits"]).flatMap { $0 <= 400 ? $0 : nil }
        return Snapshot(glucose:lastValue.map(glucose), unit:unit, timestamp:time,
            trend:data["lastSGTrend"] as? String, activeInsulin:number(active["amount"]),
            history:points.keys.sorted().map { Reading(timestamp:$0, glucose:points[$0]!) }, synthetic:false,
            reservoirUnits:reservoir,
            reservoirPercent:number(data["reservoirLevelPercent"]).flatMap { $0 <= 100 ? $0 : nil },
            pumpBatteryPercent:battery, sensorHoursLeft:sensor,
            timeInRange:TimeInRange(inRange:number(data["timeInRange"]), below:number(data["belowHypoLimit"]),
                                    above:number(data["aboveHyperLimit"])),
            smartGuardState:algorithm["autoModeShieldState"] as? String,
            safeBasalMinutes:number(algorithm["safeBasalDuration"]),
            phoneConnected:flag(data["conduitInRange"]), pumpInRange:flag(data["conduitMedicalDeviceInRange"]),
            pumpSuspended:flag(data["pumpSuspended"]), pumpCharging:flag(data["isPumpCharging"]),
            sensorStateCode:data["sensorState"] as? String, systemStatusCode:data["systemStatusMessage"] as? String,
            infusionStatusCode:data["infusionStatus"] as? String,
            infusionMinutesLeft:number(data["infusionRemainingDuration"], positive:true).flatMap { $0 <= 20_160 ? $0 : nil },
            markers:markers.sorted { $0.date < $1.date }, pumpLimits:pumpLimits)
    }
}
