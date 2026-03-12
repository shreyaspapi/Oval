import Foundation
import os

// MARK: - Model Catalog Entry

/// Describes an available STT or TTS model that can be registered, downloaded, and loaded.
struct RAModelCatalogEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let url: URL
    let size: String
    let memoryBytes: Int64
    let category: RAModelCategory
    let language: String
    let quality: String
}

enum RAModelCategory: String, Equatable {
    case stt = "STT"
    case tts = "TTS"
}

// MARK: - Model State Enum

enum RAModelState: Equatable {
    case notDownloaded
    case downloading
    case downloaded
    case loading
    case loaded
    case error(String)

    var displayName: String {
        switch self {
        case .notDownloaded: return "Not Downloaded"
        case .downloading: return "Downloading..."
        case .downloaded: return "Downloaded"
        case .loading: return "Loading..."
        case .loaded: return "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isReady: Bool {
        self == .loaded
    }
}

// MARK: - Service (Stub — RunAnywhere SDK removed)

/// No-op stub for RunAnywhere SDK. Voice mode (on-device STT/TTS) is unavailable.
@MainActor
@Observable
final class RunAnywhereService {

    static let shared = RunAnywhereService()

    // Empty catalogs — no models available without the SDK
    static let sttCatalog: [RAModelCatalogEntry] = []
    static let ttsCatalog: [RAModelCatalogEntry] = []

    var isSDKReady = false
    var sttModelState: RAModelState = .notDownloaded
    var ttsModelState: RAModelState = .notDownloaded
    var downloadProgress: Double = 0.0
    var error: String? = "RunAnywhere SDK is not available."
    var selectedSTTModelId: String = ""
    var selectedTTSModelId: String = ""
    var modelStates: [String: RAModelState] = [:]
    var modelDownloadProgress: [String: Double] = [:]
    var modelBytesDownloaded: [String: Int64] = [:]
    var isCheckingModelStates = false

    var selectedSTTModel: RAModelCatalogEntry? { nil }
    var selectedTTSModel: RAModelCatalogEntry? { nil }
    var isVoiceReady: Bool { false }

    private init() {}

    func initialize() async {}
    func refreshAllModelStates() async {}
    func downloadModel(id: String) async {}
    func downloadAndLoadModels() async {}
    func loadSelectedModels() async {}
    func selectSTTModel(_ id: String) async {}
    func selectTTSModel(_ id: String) async {}
}

// MARK: - Errors

enum RunAnywhereServiceError: LocalizedError {
    case modelNotFound(String)
    case modelNotDownloaded(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let id):    return "Model '\(id)' not found"
        case .modelNotDownloaded(let id): return "Model '\(id)' is not downloaded"
        case .downloadFailed(let msg):  return "Download failed: \(msg)"
        }
    }
}
