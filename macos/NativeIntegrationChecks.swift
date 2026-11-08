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
    static func jwt(expiry: Double) -> String {
        let claims: [String:Any] = ["exp":expiry,"token_details":["country":"PT","preferred_username":"synthetic"]]
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
        MockCareLink.handler = { request in
            requests.append(request.url!.path)
            switch request.url! {
            case Endpoints.token: return (200,["access_token":jwt(expiry:Date().timeIntervalSince1970+7200),"refresh_token":"rotated"])
            case Endpoints.discovery: return (200,["supportedCountries":[["PT":["region":"EU"]]], "CP":[["region":"EU","baseUrlCareLink":"https://carelink.minimed.eu/api/carepartner/v2","baseUrlCumulus":"https://clcloud.minimed.eu/connect/carepartner/v13"]]])
            case Endpoints.user: return failUser ? (500,[:]) : (200,["role":"PATIENT"])
            case Endpoints.display: return (200,["patientData":["bgUnits":"MGDL","clientTimeZoneName":"Europe/Lisbon","lastSG":["sg":123,"timestamp":"2026-10-28T12:00:00"],"activeInsulin":["amount":0],"sgs":[]]])
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
        print("PASS: native API read, refresh rotation, persistence after API failure, cancellation/logout race and logged-out timer")
    }
}
