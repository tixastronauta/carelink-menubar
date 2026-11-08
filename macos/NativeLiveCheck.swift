import Foundation

// Developer-only read comparison; no token migration, renewal or persistence.
final class ReadOnlyTestVault: TokenStorage {
    let tokens: Tokens
    init(_ tokens: Tokens) { self.tokens = tokens }
    func load() throws -> Tokens? { tokens }
    func save(_ tokens: Tokens) throws { throw CareLinkError.configuration }
    func clear() throws { throw CareLinkError.configuration }
}

@main struct NativeLiveCheck {
    @MainActor static func main() async {
        do {
            let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CarelinkPrototype/logindata.json")
            let object = try JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any] ?? [:]
            guard let id = object["client_id"] as? String else { throw CareLinkError.authentication }
            let tokens = try Tokens.response(object,clientID:id)
            let api = NativeAPI(vault:ReadOnlyTestVault(tokens))
            let snapshot = try await api.fetch(allowRenewal:false)
            guard snapshot.sensorDate != nil, snapshot.glucose != nil, !snapshot.points.isEmpty else { throw CareLinkError.schema }
            print("PASS: native authenticated EU read; glucose, timestamp and history parsed; no renewal, token migration or persistence")
            print("History points: \(snapshot.points.count)")
        } catch {
            print("Native read check failed; sensitive details suppressed.")
            exit(1)
        }
    }
}
