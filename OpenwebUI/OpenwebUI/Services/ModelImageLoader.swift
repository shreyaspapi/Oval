import SwiftUI
import AppKit

/// Async image loader for model profile images.
/// Fetches images from the Open WebUI server endpoint with proper authentication,
/// and caches them in memory to avoid redundant network requests.
@MainActor
final class ModelImageLoader {

    static let shared = ModelImageLoader()

    private var cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private init() {
        cache.countLimit = 200
    }

    /// Get a cached image or fetch it from the server.
    func image(for modelID: String, serverURL: String, apiKey: String) async -> NSImage? {
        let cacheKey = NSString(string: "\(serverURL)|\(modelID)")

        // Check cache first
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Check if already in flight
        if let existing = inFlight[modelID] {
            return await existing.value
        }

        // Start fetch
        let task = Task<NSImage?, Never> {
            let urlString = "\(serverURL)/models/model/profile/image?id=\(modelID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? modelID)"
            guard let url = URL(string: urlString) else { return nil }

            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    return nil
                }
                guard let image = NSImage(data: data) else { return nil }
                cache.setObject(image, forKey: cacheKey)
                return image
            } catch {
                return nil
            }
        }

        inFlight[modelID] = task
        let result = await task.value
        inFlight.removeValue(forKey: modelID)
        return result
    }

    /// Clear the image cache (e.g., when switching servers).
    func clearCache() {
        cache.removeAllObjects()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }
}

// MARK: - Model Avatar View

/// Displays a model's profile image with an async load and fallback icon.
struct ModelAvatarView: View {
    let model: AIModel
    let serverURL: String
    let apiKey: String
    let size: CGFloat

    @State private var image: NSImage?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Fallback: icon based on model type
                Image(systemName: fallbackIcon)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
        .background(
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(AppColors.avatarBg)
        )
        .task(id: model.id) {
            guard !didLoad else { return }
            didLoad = true
            image = await ModelImageLoader.shared.image(
                for: model.id,
                serverURL: serverURL,
                apiKey: apiKey
            )
        }
    }

    private var fallbackIcon: String {
        switch model.connectionCategory {
        case .local:    return "cpu"
        case .external: return "cloud"
        case .unknown:
            if model.isPipe { return "gearshape.2" }
            return "sparkle"
        }
    }
}
