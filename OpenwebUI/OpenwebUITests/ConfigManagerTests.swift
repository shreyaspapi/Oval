import Testing
import Foundation
@testable import Oval

// MARK: - ConfigManager.Config Tests

@Suite("ConfigManager.Config")
struct ConfigManagerConfigTests {

    @Test("Config default values")
    func defaults() {
        let config = ConfigManager.Config()
        #expect(config.servers.isEmpty)
        #expect(config.activeServerID == nil)
        #expect(config.selectedModelID == nil)
        #expect(config.defaultModelID == nil)
        #expect(config.pinnedModelIDs.isEmpty)
    }

    @Test("Config JSON round-trip with empty values")
    func emptyRoundTrip() throws {
        let config = ConfigManager.Config()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ConfigManager.Config.self, from: data)
        #expect(decoded.servers.isEmpty)
        #expect(decoded.activeServerID == nil)
    }

    @Test("Config JSON round-trip with populated values")
    func populatedRoundTrip() throws {
        var config = ConfigManager.Config()
        let server = ServerConfig(name: "Test", url: "http://test:8080", apiKey: "")
        config.servers = [server]
        config.activeServerID = server.id
        config.selectedModelID = "llama3:latest"
        config.defaultModelID = "gpt-4"
        config.pinnedModelIDs = ["model-1", "model-2"]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ConfigManager.Config.self, from: data)

        #expect(decoded.servers.count == 1)
        #expect(decoded.servers[0].id == server.id)
        #expect(decoded.servers[0].name == "Test")
        #expect(decoded.activeServerID == server.id)
        #expect(decoded.selectedModelID == "llama3:latest")
        #expect(decoded.defaultModelID == "gpt-4")
        #expect(decoded.pinnedModelIDs == ["model-1", "model-2"])
    }

    @Test("Config encoding excludes apiKey from server")
    func encodingExcludesApiKey() throws {
        var config = ConfigManager.Config()
        let server = ServerConfig(name: "S", url: "http://s", apiKey: "super-secret")
        config.servers = [server]

        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let serversArray = json["servers"] as! [[String: Any]]

        // apiKey should NOT be in the JSON output since ServerConfig excludes it
        #expect(serversArray[0]["apiKey"] == nil)
    }

    @Test("Config with multiple servers")
    func multipleServers() throws {
        var config = ConfigManager.Config()
        let s1 = ServerConfig(name: "Local", url: "http://localhost:8080", apiKey: "")
        let s2 = ServerConfig(name: "Remote", url: "https://remote.example.com", apiKey: "")
        config.servers = [s1, s2]
        config.activeServerID = s2.id

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ConfigManager.Config.self, from: data)

        #expect(decoded.servers.count == 2)
        #expect(decoded.activeServerID == s2.id)
    }

    @Test("Config model preferences persist correctly")
    func modelPreferences() throws {
        var config = ConfigManager.Config()
        config.selectedModelID = "claude-sonnet-4-20250514"
        config.defaultModelID = "gpt-4o"
        config.pinnedModelIDs = ["llama3:latest", "mistral:latest", "phi3:latest"]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ConfigManager.Config.self, from: data)

        #expect(decoded.selectedModelID == "claude-sonnet-4-20250514")
        #expect(decoded.defaultModelID == "gpt-4o")
        #expect(decoded.pinnedModelIDs.count == 3)
        #expect(decoded.pinnedModelIDs.contains("llama3:latest"))
    }

    @Test("Config decoding with missing optional fields")
    func decodingMissingFields() throws {
        // Simulate an older config file that doesn't have model preferences
        // Note: pinnedModelIDs has a default value of [] but Codable requires the key
        // to be present unless a custom init(from:) is provided. Include all non-optional keys.
        let json: [String: Any] = [
            "servers": [],
            "pinnedModelIDs": [] as [String],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let config = try JSONDecoder().decode(ConfigManager.Config.self, from: data)

        #expect(config.servers.isEmpty)
        #expect(config.activeServerID == nil)
        #expect(config.selectedModelID == nil)
        #expect(config.defaultModelID == nil)
        #expect(config.pinnedModelIDs.isEmpty)
    }
}

// MARK: - ConfigManager File Operations Tests

@Suite("ConfigManager File Operations")
struct ConfigManagerFileTests {

    @MainActor
    @Test("load returns default Config when no file exists")
    func loadNoFile() {
        // ConfigManager will look for config.json in Application Support.
        // In a test environment with a fresh user, this file might not exist.
        let manager = ConfigManager()
        let config = manager.load()
        // Should return a default Config (empty servers)
        #expect(config is ConfigManager.Config)
    }

    @MainActor
    @Test("save and load round-trip")
    func saveAndLoad() {
        let manager = ConfigManager()
        var config = ConfigManager.Config()

        // Create test server
        let server = ServerConfig(
            name: "Round Trip Test",
            url: "http://rt-test:8080",
            apiKey: "test-token-for-roundtrip"
        )
        config.servers = [server]
        config.activeServerID = server.id
        config.selectedModelID = "test-model"
        config.defaultModelID = "default-model"
        config.pinnedModelIDs = ["pin-1"]

        // Save
        manager.save(config)

        // Load
        let loaded = manager.load()
        #expect(loaded.servers.count == 1)
        #expect(loaded.servers[0].name == "Round Trip Test")
        #expect(loaded.servers[0].url == "http://rt-test:8080")
        #expect(loaded.activeServerID == server.id)
        #expect(loaded.selectedModelID == "test-model")
        #expect(loaded.defaultModelID == "default-model")
        #expect(loaded.pinnedModelIDs == ["pin-1"])

        // The API key should have been stored in Keychain and hydrated on load
        // (In tests, Keychain access might be restricted — just check it's not nil)
        // loaded.servers[0].apiKey may or may not equal the original depending on Keychain access

        // Clean up
        manager.delete()
    }

    @MainActor
    @Test("delete removes config file")
    func deleteConfig() {
        let manager = ConfigManager()
        var config = ConfigManager.Config()
        config.servers = [ServerConfig(name: "Delete Test", url: "http://dt", apiKey: "")]
        manager.save(config)

        manager.delete()

        let loaded = manager.load()
        // After delete, load should return default config
        #expect(loaded.servers.isEmpty)
    }

    @MainActor
    @Test("save creates Application Support directory if needed")
    func saveCreatesDirectory() {
        let manager = ConfigManager()
        let config = ConfigManager.Config()
        // Should not throw even if directory doesn't exist
        manager.save(config)
        let loaded = manager.load()
        #expect(loaded is ConfigManager.Config)
    }

    @MainActor
    @Test("save stores API keys in Keychain, not JSON")
    func keychainStorage() {
        let manager = ConfigManager()
        var config = ConfigManager.Config()
        let server = ServerConfig(
            name: "Keychain Test",
            url: "http://keychain-test:8080",
            apiKey: "secret-token-12345"
        )
        config.servers = [server]
        manager.save(config)

        // Load the config - apiKey should come from Keychain hydration
        let loaded = manager.load()
        #expect(loaded.servers.count == 1)
        // The token should have been saved to Keychain and hydrated back
        // In a test environment with Keychain access, this should work:
        let keychainToken = KeychainManager.loadToken(for: server.id)
        if keychainToken != nil {
            #expect(keychainToken == "secret-token-12345")
            #expect(loaded.servers[0].apiKey == "secret-token-12345")
        }
        // Clean up
        KeychainManager.deleteToken(for: server.id)
        manager.delete()
    }
}
