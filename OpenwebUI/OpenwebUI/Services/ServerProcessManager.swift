import Foundation

/// Lightweight service that only checks if a remote Open WebUI server is reachable.
/// No Python, no process management — just health checks.
@MainActor
final class ServerConnectionManager {
    /// Check if the server at the given URL is reachable via /health or /api/version.
    func checkHealth(url: String) async -> Bool {
        // Try /health first, then /api/version as fallback
        for path in ["/health", "/api/version"] {
            guard let endpoint = URL(string: "\(url)\(path)") else { continue }

            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 5

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse,
                   (200...299).contains(http.statusCode) {
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }

    /// Fetch server version info if available.
    func fetchVersion(url: String) async -> String? {
        guard let endpoint = URL(string: "\(url)/api/version") else { return nil }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = json["version"] as? String {
                return version
            }
        } catch {}
        return nil
    }
}
