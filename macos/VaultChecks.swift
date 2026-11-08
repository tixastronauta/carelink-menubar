import Foundation

@main struct VaultChecks {
    static func main() throws {
        let vault = CredentialVault(service:"local.tcx.carelink.menu.test." + UUID().uuidString)
        defer { try? vault.clear() }
        let empty = try vault.load()
        precondition(empty == nil)
        try vault.save(Tokens(accessToken:"synthetic-access", refreshToken:"synthetic-refresh", clientID:"synthetic-client"))
        let saved = try vault.load()
        precondition(saved?.refreshToken == "synthetic-refresh")
        try vault.save(Tokens(accessToken:"synthetic-access-2", refreshToken:"synthetic-rotated", clientID:"synthetic-client"))
        let updated = try vault.load()
        precondition(updated?.refreshToken == "synthetic-rotated")
        try vault.clear()
        let removed = try vault.load()
        precondition(removed == nil)
        print("PASS: isolated Keychain create/read/update/delete; synthetic item removed")
    }
}
