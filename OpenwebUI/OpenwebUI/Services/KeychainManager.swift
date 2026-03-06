import Foundation
import Security

/// Manages secure storage of API keys and JWT tokens in the macOS Keychain.
/// Uses the Security framework directly — no third-party dependencies.
enum KeychainManager {

    private static let service = "com.shreyas.oval"

    // MARK: - Save

    /// Save a token to the Keychain for a given server ID.
    @discardableResult
    static func saveToken(_ token: String, for serverID: UUID) -> Bool {
        let account = serverID.uuidString
        guard let data = token.data(using: .utf8) else { return false }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add the new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Load

    /// Load a token from the Keychain for a given server ID.
    static func loadToken(for serverID: UUID) -> String? {
        let account = serverID.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return token
    }

    // MARK: - Delete

    /// Delete a token from the Keychain for a given server ID.
    @discardableResult
    static func deleteToken(for serverID: UUID) -> Bool {
        let account = serverID.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Delete All

    /// Delete all tokens stored by this app.
    @discardableResult
    static func deleteAllTokens() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
