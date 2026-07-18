import Foundation
import Security

/// Minimal Keychain wrapper for small secrets (the auth session).
/// Tokens never touch UserDefaults.
enum KeychainStore {

    private static let service = "in.adsys.riva"

    static func save(_ data: Data, key: String) {
        var query = baseQuery(key: key)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> Data? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(key: String) {
        SecItemDelete(baseQuery(key: key) as CFDictionary)
    }

    private static func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
