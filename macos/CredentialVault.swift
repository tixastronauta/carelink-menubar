import Foundation
import Security

protocol TokenStorage {
    func load() throws -> Tokens?
    func save(_ tokens: Tokens) throws
    func clear() throws
}

struct CredentialVault: TokenStorage {
    private let service: String
    init(service: String = "local.tcx.carelink.menu.oauth.eu") { self.service = service }
    private var query: [String:Any] {
        [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service,
         kSecAttrAccount as String:"carelink-session", kSecAttrSynchronizable as String:false]
    }
    func load() throws -> Tokens? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data,
              let tokens = try? JSONDecoder().decode(Tokens.self, from:data) else { throw CareLinkError.keychain }
        return tokens
    }
    func save(_ tokens: Tokens) throws {
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String:Any] = [kSecValueData as String:data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(request as CFDictionary,nil) == errSecSuccess else { throw CareLinkError.keychain }
        } else if status != errSecSuccess { throw CareLinkError.keychain }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CareLinkError.keychain }
    }
}
