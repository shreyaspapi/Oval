import Testing
import Foundation
@testable import Oval

@Suite("KeychainManager")
struct KeychainManagerTests {

    // Use a unique server ID per test to avoid cross-contamination
    private func uniqueServerID() -> UUID { UUID() }

    @Test("save and load token")
    func saveAndLoad() {
        let id = uniqueServerID()
        let token = "test-token-\(id.uuidString)"

        let saved = KeychainManager.saveToken(token, for: id)
        #expect(saved == true)

        let loaded = KeychainManager.loadToken(for: id)
        #expect(loaded == token)

        // Cleanup
        KeychainManager.deleteToken(for: id)
    }

    @Test("load returns nil for non-existent token")
    func loadNonExistent() {
        let id = uniqueServerID()
        let loaded = KeychainManager.loadToken(for: id)
        #expect(loaded == nil)
    }

    @Test("delete removes token")
    func deleteToken() {
        let id = uniqueServerID()
        KeychainManager.saveToken("to-delete", for: id)

        let deleted = KeychainManager.deleteToken(for: id)
        #expect(deleted == true)

        let loaded = KeychainManager.loadToken(for: id)
        #expect(loaded == nil)
    }

    @Test("delete non-existent token succeeds")
    func deleteNonExistent() {
        let id = uniqueServerID()
        let result = KeychainManager.deleteToken(for: id)
        // Should succeed (errSecItemNotFound is treated as success)
        #expect(result == true)
    }

    @Test("save overwrites existing token")
    func saveOverwrite() {
        let id = uniqueServerID()
        KeychainManager.saveToken("original", for: id)
        KeychainManager.saveToken("updated", for: id)

        let loaded = KeychainManager.loadToken(for: id)
        #expect(loaded == "updated")

        KeychainManager.deleteToken(for: id)
    }

    @Test("save empty string token")
    func saveEmptyString() {
        let id = uniqueServerID()
        let saved = KeychainManager.saveToken("", for: id)
        #expect(saved == true)

        let loaded = KeychainManager.loadToken(for: id)
        #expect(loaded == "")

        KeychainManager.deleteToken(for: id)
    }

    @Test("save long token")
    func saveLongToken() {
        let id = uniqueServerID()
        let longToken = String(repeating: "a", count: 10000)
        KeychainManager.saveToken(longToken, for: id)

        let loaded = KeychainManager.loadToken(for: id)
        #expect(loaded == longToken)

        KeychainManager.deleteToken(for: id)
    }

    @Test("save token with special characters")
    func saveSpecialChars() {
        let id = uniqueServerID()
        let token = "sk-abc123!@#$%^&*()_+-=[]{}|;':\",./<>?"
        KeychainManager.saveToken(token, for: id)

        let loaded = KeychainManager.loadToken(for: id)
        #expect(loaded == token)

        KeychainManager.deleteToken(for: id)
    }

    @Test("multiple servers have independent tokens")
    func multipleServers() {
        let id1 = uniqueServerID()
        let id2 = uniqueServerID()

        KeychainManager.saveToken("token-1", for: id1)
        KeychainManager.saveToken("token-2", for: id2)

        #expect(KeychainManager.loadToken(for: id1) == "token-1")
        #expect(KeychainManager.loadToken(for: id2) == "token-2")

        KeychainManager.deleteToken(for: id1)
        KeychainManager.deleteToken(for: id2)
    }
}
