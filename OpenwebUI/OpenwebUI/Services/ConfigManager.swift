import Foundation

/// Persists user configuration to config.json in the app support directory.
@MainActor
final class ConfigManager {
    struct Config: Codable {
        var servers: [ServerConfig] = []
        var activeServerID: UUID?
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
        guard fileManager.fileExists(atPath: configFileURL.path()) else {
            return Config()
        }
        do {
            let data = try Data(contentsOf: configFileURL)
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            return Config()
        }
    }

    func save(_ config: Config) {
        let dir = configFileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
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
        try? fileManager.removeItem(at: configFileURL)
    }
}
