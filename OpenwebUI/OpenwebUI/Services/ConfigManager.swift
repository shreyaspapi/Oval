import Foundation

/// Persists user configuration to config.json in the app support directory.
/// API keys and JWT tokens are stored securely in the macOS Keychain — never in the JSON file.
@MainActor
final class ConfigManager {
    struct Config: Codable {
        var servers: [ServerConfig] = []
        var activeServerID: UUID?

        // Model preferences
        var selectedModelID: String?      // Last-used model ID (restored on launch)
        var defaultModelID: String?       // User's explicit default model (fallback if selected is gone)
        var pinnedModelIDs: [String] = [] // Pinned/favorite model IDs shown in the sidebar
    }

    private let fileManager = FileManager.default

    private var configFileURL: URL {
        let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("OpenWebUI")
        return appSupport.appendingPathComponent("config.json")
    }

    func load() -> Config {
        // IMPORTANT: Use .path (property) NOT .path() (method).
        // .path() returns percent-encoded strings (e.g. "Application%20Support")
        // which FileManager cannot find on disk.
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            return Config()
        }
        do {
            let data = try Data(contentsOf: configFileURL)
            var config = try JSONDecoder().decode(Config.self, from: data)

            // Hydrate API keys from the Keychain (they are not stored in the JSON file)
            for i in config.servers.indices {
                if let token = KeychainManager.loadToken(for: config.servers[i].id) {
                    config.servers[i].apiKey = token
                }
                // Migration: if the JSON file still has an apiKey field from an older version,
                // read it via a migration decoder and move it to Keychain
                if config.servers[i].apiKey.isEmpty {
                    if let legacyToken = loadLegacyApiKey(from: data, serverID: config.servers[i].id) {
                        config.servers[i].apiKey = legacyToken
                        KeychainManager.saveToken(legacyToken, for: config.servers[i].id)
                    }
                }
            }

            return config
        } catch {
            return Config()
        }
    }

    func save(_ config: Config) {
        let dir = configFileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        // Save API keys to Keychain
        for server in config.servers {
            if !server.apiKey.isEmpty {
                KeychainManager.saveToken(server.apiKey, for: server.id)
            }
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configFileURL, options: .atomic)
        } catch {
            print("[ConfigManager] Failed to save: \(error)")
        }
    }

    func delete() {
        // Delete all Keychain tokens
        KeychainManager.deleteAllTokens()
        try? fileManager.removeItem(at: configFileURL)
    }

    // MARK: - Legacy Migration

    /// Attempt to read an `apiKey` field from older config.json format where apiKey
    /// was stored in plaintext alongside the other server fields.
    private func loadLegacyApiKey(from data: Data, serverID: UUID) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let serversArray = json["servers"] as? [[String: Any]]
        else { return nil }

        for serverDict in serversArray {
            if let idString = serverDict["id"] as? String,
               UUID(uuidString: idString) == serverID,
               let apiKey = serverDict["apiKey"] as? String,
               !apiKey.isEmpty {
                return apiKey
            }
        }
        return nil
    }
}
