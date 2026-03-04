import Foundation
import RunAnywhere
import ONNXRuntime
import WhisperKitRuntime
import os

// MARK: - Model Catalog Entry

/// Describes an available STT or TTS model that can be registered, downloaded, and loaded.
struct RAModelCatalogEntry: Identifiable, Equatable {
    let id: String                   // e.g. "sherpa-onnx-whisper-tiny.en"
    let name: String                 // e.g. "Whisper Tiny EN"
    let description: String          // Short description
    let url: URL                     // Download URL
    let size: String                 // Human-readable, e.g. "~75 MB"
    let memoryBytes: Int64            // For SDK registration
    let category: RAModelCategory    // .stt or .tts
    let language: String             // e.g. "English"
    let quality: String              // e.g. "Good", "Better", "Best"
}

enum RAModelCategory: String, Equatable {
    case stt = "STT"
    case tts = "TTS"
}

// MARK: - Service

/// Manages RunAnywhere SDK initialization, model registration, download, and loading.
/// Provides on-device STT (speech-to-text) and TTS (text-to-speech) for voice mode.
///
/// WORKAROUND: The SDK's `ModelInfo(from:)` C++ bridge crashes (EXC_BAD_ACCESS) when
/// reading the `description` field from `rac_model_info_t`. We keep our own Swift-side
/// `ModelInfo` objects and bypass the C++ registry entirely.
@MainActor
@Observable
final class RunAnywhereService {

    // MARK: - Singleton

    static let shared = RunAnywhereService()

    // MARK: - Model Catalog

    /// All available STT models the user can choose from.
    static let sttCatalog: [RAModelCatalogEntry] = [
        RAModelCatalogEntry(
            id: "sherpa-onnx-whisper-tiny.en",
            name: "Whisper Tiny EN",
            description: "Fastest, low memory. Good for quick commands.",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz")!,
            size: "~75 MB",
            memoryBytes: 75_000_000,
            category: .stt,
            language: "English",
            quality: "Good"
        ),
        RAModelCatalogEntry(
            id: "sherpa-onnx-moonshine-base-en-int8",
            name: "Moonshine Base EN",
            description: "Best accuracy with int8 quantization. Great for dictation.",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/sherpa-onnx-moonshine-base-en-int8.tar.gz")!,
            size: "~100 MB",
            memoryBytes: 100_000_000,
            category: .stt,
            language: "English",
            quality: "Best"
        ),
        RAModelCatalogEntry(
            id: "whisperkit-tiny.en",
            name: "WhisperKit Tiny EN",
            description: "Runs on Apple Neural Engine. Fastest, lowest battery.",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/whisperkit-tiny.en.tar.gz")!,
            size: "~70 MB",
            memoryBytes: 70_000_000,
            category: .stt,
            language: "English",
            quality: "Good"
        ),
        RAModelCatalogEntry(
            id: "whisperkit-base.en",
            name: "WhisperKit Base EN",
            description: "Neural Engine, higher accuracy. Recommended for Mac.",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/whisperkit-base.en.tar.gz")!,
            size: "~134 MB",
            memoryBytes: 134_000_000,
            category: .stt,
            language: "English",
            quality: "Better"
        ),
    ]

    /// All available TTS voices the user can choose from.
    static let ttsCatalog: [RAModelCatalogEntry] = [
        RAModelCatalogEntry(
            id: "vits-piper-en_US-lessac-medium",
            name: "Lessac (US Male)",
            description: "Natural American male voice. Recommended default.",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz")!,
            size: "~65 MB",
            memoryBytes: 65_000_000,
            category: .tts,
            language: "English (US)",
            quality: "Medium"
        ),
        RAModelCatalogEntry(
            id: "kokoro-en-v0_19",
            name: "Kokoro EN",
            description: "High-quality neural voice. Expressive and natural.",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/kokoro-en-v0_19.tar.gz")!,
            size: "~350 MB",
            memoryBytes: 350_000_000,
            category: .tts,
            language: "English (US)",
            quality: "Best"
        ),
        RAModelCatalogEntry(
            id: "vits-piper-en_GB-alba-medium",
            name: "Alba (British Female)",
            description: "Scottish/British female voice.",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz")!,
            size: "~65 MB",
            memoryBytes: 65_000_000,
            category: .tts,
            language: "English (UK)",
            quality: "Medium"
        ),
    ]

    // MARK: - State

    var isSDKReady = false
    var sttModelState: RAModelState = .notDownloaded
    var ttsModelState: RAModelState = .notDownloaded
    var downloadProgress: Double = 0.0
    var error: String?

    /// Currently selected STT model ID (persisted in UserDefaults).
    var selectedSTTModelId: String

    /// Currently selected TTS model ID (persisted in UserDefaults).
    var selectedTTSModelId: String

    /// Per-model download states (for catalog UI).
    var modelStates: [String: RAModelState] = [:]

    /// Per-model download progress: fraction (0.0–1.0)
    var modelDownloadProgress: [String: Double] = [:]
    /// Per-model bytes downloaded so far
    var modelBytesDownloaded: [String: Int64] = [:]

    // MARK: - Computed

    var selectedSTTModel: RAModelCatalogEntry? {
        Self.sttCatalog.first { $0.id == selectedSTTModelId }
    }

    var selectedTTSModel: RAModelCatalogEntry? {
        Self.ttsCatalog.first { $0.id == selectedTTSModelId }
    }

    /// Whether both selected STT and TTS models are loaded and ready.
    var isVoiceReady: Bool {
        sttModelState == .loaded && ttsModelState == .loaded
    }

    // MARK: - Private

    private let logger = Logger(subsystem: "com.oval.app", category: "RunAnywhere")
    private var isInitialized = false

    /// Local cache of ModelInfo objects created at registration time.
    private var registeredModels: [String: ModelInfo] = [:]

    /// Serializes model downloads so only one runs at a time (avoids -422 and
    /// shared-state races on `downloadProgress`).
    private var downloadQueue: [String] = []
    private var isDownloading = false

    private init() {
        // Restore user's model selections (or use defaults)
        self.selectedSTTModelId = UserDefaults.standard.string(forKey: "ra_selected_stt")
            ?? Self.sttCatalog.first!.id
        self.selectedTTSModelId = UserDefaults.standard.string(forKey: "ra_selected_tts")
            ?? Self.ttsCatalog.first!.id
    }

    // MARK: - SDK Initialization

    /// Initialize the RunAnywhere SDK and register ALL catalog models.
    /// Call this once at app startup.
    func initialize() async {
        guard !isInitialized else { return }

        do {
            try RunAnywhere.initialize(environment: .development)
            ONNX.register(priority: 100)
            WhisperKitSTT.register(priority: 200)

            // Register all catalog models so any can be downloaded/loaded
            for entry in Self.sttCatalog {
                let framework: InferenceFramework = entry.id.hasPrefix("whisperkit") ? .whisperKitCoreML : .onnx
                let info = RunAnywhere.registerModel(
                    id: entry.id,
                    name: entry.name,
                    url: entry.url,
                    framework: framework,
                    modality: .speechRecognition,
                    artifactType: .archive(.tarGz, structure: .nestedDirectory),
                    memoryRequirement: entry.memoryBytes
                )
                registeredModels[entry.id] = info
            }

            for entry in Self.ttsCatalog {
                let info = RunAnywhere.registerModel(
                    id: entry.id,
                    name: entry.name,
                    url: entry.url,
                    framework: .onnx,
                    modality: .speechSynthesis,
                    artifactType: .archive(.tarGz, structure: .nestedDirectory),
                    memoryRequirement: entry.memoryBytes
                )
                registeredModels[entry.id] = info
            }

            isInitialized = true
            isSDKReady = true

            // Refresh download/load states for all models
            await refreshAllModelStates()

            // Auto-load selected models if already downloaded
            if sttModelState == .downloaded || ttsModelState == .downloaded {
                logger.info("Selected models already downloaded, auto-loading...")
                await loadSelectedModels()
            }

            logger.info("RunAnywhere SDK initialized with \(Self.sttCatalog.count) STT + \(Self.ttsCatalog.count) TTS models")
        } catch {
            self.error = "Failed to initialize RunAnywhere: \(error.localizedDescription)"
            logger.error("RunAnywhere init failed: \(error)")
        }
    }

    // MARK: - Model State

    /// Refresh states for all catalog models + the selected ones.
    func refreshAllModelStates() async {
        guard isSDKReady else { return }

        // Check every catalog model's download state
        let allEntries = Self.sttCatalog + Self.ttsCatalog
        for entry in allEntries {
            let framework: InferenceFramework = entry.id.hasPrefix("whisperkit") ? .whisperKitCoreML : .onnx
            if isModelDownloaded(modelId: entry.id, framework: framework) {
                modelStates[entry.id] = .downloaded
            } else {
                modelStates[entry.id] = .notDownloaded
            }
        }

        // Check if selected models are loaded
        if await RunAnywhere.isSTTModelLoaded {
            sttModelState = .loaded
            modelStates[selectedSTTModelId] = .loaded
        } else {
            sttModelState = modelStates[selectedSTTModelId] ?? .notDownloaded
        }

        if await RunAnywhere.isTTSVoiceLoaded {
            ttsModelState = .loaded
            modelStates[selectedTTSModelId] = .loaded
        } else {
            ttsModelState = modelStates[selectedTTSModelId] ?? .notDownloaded
        }
    }

    /// Check if a model is downloaded by looking for files on disk.
    private func isModelDownloaded(modelId: String, framework: InferenceFramework) -> Bool {
        guard let modelFolder = try? CppBridge.ModelPaths.getModelFolder(
            modelId: modelId, framework: framework
        ) else {
            return false
        }
        return hasModelFiles(at: modelFolder)
            || hasModelFiles(at: modelFolder.appendingPathComponent(modelId))
    }

    // MARK: - Download a Single Model

    /// Download a specific model by ID. Downloads are serialized — if another
    /// download is in progress, this one is queued and will start automatically.
    func downloadModel(id: String) async {
        guard isSDKReady else {
            error = "SDK not ready"
            return
        }
        guard registeredModels[id] != nil else {
            error = "Model not registered: \(id)"
            return
        }

        // Mark as queued/downloading in the UI immediately
        error = nil
        modelStates[id] = .downloading
        if id == selectedSTTModelId { sttModelState = .downloading }
        if id == selectedTTSModelId { ttsModelState = .downloading }

        // If another download is running, queue this one and wait
        if isDownloading {
            if !downloadQueue.contains(id) {
                downloadQueue.append(id)
                logger.info("Queued download: \(id) (queue depth: \(self.downloadQueue.count))")
            }
            // Wait for our turn — poll until we're the active download
            while downloadQueue.first != id || isDownloading {
                try? await Task.sleep(for: .milliseconds(200))
                // If we were removed from queue (e.g. cancelled), bail
                if !downloadQueue.contains(id) && isDownloading { return }
                // If another download finished and we're next, break
                if !isDownloading && downloadQueue.first == id { break }
            }
            // Remove ourselves from the head of the queue
            downloadQueue.removeAll { $0 == id }
        }

        isDownloading = true
        downloadProgress = 0.0
        modelDownloadProgress[id] = 0.0
        modelBytesDownloaded[id] = 0

        do {
            try await downloadModelSafe(modelId: id) { [weak self] progress in
                self?.downloadProgress = progress
                self?.modelDownloadProgress[id] = progress
            }
            modelStates[id] = .downloaded
            downloadProgress = 1.0
            modelDownloadProgress[id] = 1.0
            logger.info("Model downloaded: \(id)")

            if id == selectedSTTModelId { sttModelState = .downloaded }
            if id == selectedTTSModelId { ttsModelState = .downloaded }
        } catch {
            modelStates[id] = .error(error.localizedDescription)
            self.error = "Download failed: \(error.localizedDescription)"
            logger.error("Download failed for \(id): \(error)")

            if id == selectedSTTModelId { sttModelState = .error(error.localizedDescription) }
            if id == selectedTTSModelId { ttsModelState = .error(error.localizedDescription) }
        }

        isDownloading = false
    }

    // MARK: - Download & Load Selected Models

    /// Download and load both selected STT and TTS models.
    func downloadAndLoadModels() async {
        guard isSDKReady else {
            error = "SDK not ready"
            return
        }

        error = nil
        downloadProgress = 0.0

        // Download STT if needed
        if sttModelState == .notDownloaded {
            sttModelState = .downloading
            modelStates[selectedSTTModelId] = .downloading
            do {
                try await downloadModelSafe(modelId: selectedSTTModelId) { [weak self] progress in
                    self?.downloadProgress = progress * 0.5
                }
                sttModelState = .downloaded
                modelStates[selectedSTTModelId] = .downloaded
                logger.info("STT model downloaded: \(self.selectedSTTModelId)")
            } catch {
                sttModelState = .error(error.localizedDescription)
                modelStates[selectedSTTModelId] = .error(error.localizedDescription)
                self.error = "STT download failed: \(error.localizedDescription)"
                return
            }
        }

        // Download TTS if needed
        if ttsModelState == .notDownloaded {
            ttsModelState = .downloading
            modelStates[selectedTTSModelId] = .downloading
            do {
                try await downloadModelSafe(modelId: selectedTTSModelId) { [weak self] progress in
                    self?.downloadProgress = 0.5 + progress * 0.5
                }
                ttsModelState = .downloaded
                modelStates[selectedTTSModelId] = .downloaded
                logger.info("TTS model downloaded: \(self.selectedTTSModelId)")
            } catch {
                ttsModelState = .error(error.localizedDescription)
                modelStates[selectedTTSModelId] = .error(error.localizedDescription)
                self.error = "TTS download failed: \(error.localizedDescription)"
                return
            }
        }

        downloadProgress = 1.0
        await loadSelectedModels()
    }

    /// Load the currently selected STT and TTS models into memory.
    func loadSelectedModels() async {
        guard isSDKReady else { return }

        if sttModelState == .downloaded {
            sttModelState = .loading
            modelStates[selectedSTTModelId] = .loading
            do {
                try await loadSTTModelSafe(selectedSTTModelId)
                sttModelState = .loaded
                modelStates[selectedSTTModelId] = .loaded
                logger.info("STT model loaded: \(self.selectedSTTModelId)")
            } catch {
                sttModelState = .error(error.localizedDescription)
                modelStates[selectedSTTModelId] = .error(error.localizedDescription)
                self.error = "STT load failed: \(error.localizedDescription)"
            }
        }

        if ttsModelState == .downloaded {
            ttsModelState = .loading
            modelStates[selectedTTSModelId] = .loading
            do {
                try await loadTTSVoiceSafe(selectedTTSModelId)
                ttsModelState = .loaded
                modelStates[selectedTTSModelId] = .loaded
                logger.info("TTS voice loaded: \(self.selectedTTSModelId)")
            } catch {
                ttsModelState = .error(error.localizedDescription)
                modelStates[selectedTTSModelId] = .error(error.localizedDescription)
                self.error = "TTS load failed: \(error.localizedDescription)"
            }
        }
    }

    /// Change the selected STT model. If already downloaded, loads it immediately.
    func selectSTTModel(_ id: String) async {
        selectedSTTModelId = id
        UserDefaults.standard.set(id, forKey: "ra_selected_stt")
        let state = modelStates[id] ?? .notDownloaded
        sttModelState = state
        if state == .downloaded {
            sttModelState = .loading
            modelStates[id] = .loading
            do {
                try await loadSTTModelSafe(id)
                sttModelState = .loaded
                modelStates[id] = .loaded
            } catch {
                sttModelState = .error(error.localizedDescription)
                modelStates[id] = .error(error.localizedDescription)
            }
        }
    }

    /// Change the selected TTS model. If already downloaded, loads it immediately.
    func selectTTSModel(_ id: String) async {
        selectedTTSModelId = id
        UserDefaults.standard.set(id, forKey: "ra_selected_tts")
        let state = modelStates[id] ?? .notDownloaded
        ttsModelState = state
        if state == .downloaded {
            ttsModelState = .loading
            modelStates[id] = .loading
            do {
                try await loadTTSVoiceSafe(id)
                ttsModelState = .loaded
                modelStates[id] = .loaded
            } catch {
                ttsModelState = .error(error.localizedDescription)
                modelStates[id] = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Safe Model Operations (Bypass C++ Bridge Crash)

    /// Download a model directly via URLSession, bypassing CppBridge.Download
    /// which crashes with -422 (RAC_ERROR_NO_CAPABLE_PROVIDER).
    /// We still use CppBridge.ModelPaths for the destination folder and
    /// the SDK's DefaultExtractionService for tar.gz extraction.
    private func downloadModelSafe(
        modelId: String,
        progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard let modelInfo = registeredModels[modelId] else {
            throw RunAnywhereServiceError.modelNotFound(modelId)
        }
        guard let downloadURL = modelInfo.downloadURL else {
            throw RunAnywhereServiceError.downloadFailed("No download URL for model: \(modelId)")
        }

        // Get destination folder from SDK path utilities (this still works)
        let destinationFolder = try CppBridge.ModelPaths.getModelFolder(
            modelId: modelId, framework: modelInfo.framework
        )

        // Create destination folder if needed
        try FileManager.default.createDirectory(
            at: destinationFolder, withIntermediateDirectories: true
        )

        // Check if already downloaded
        if hasModelFiles(at: destinationFolder)
            || hasModelFiles(at: destinationFolder.appendingPathComponent(modelId)) {
            logger.info("Model already downloaded: \(modelId)")
            await progressHandler(1.0)
            return
        }

        logger.info("Starting direct download for \(modelId) from \(downloadURL)")

        // Download to a temp file using URLSession with progress tracking
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(modelId)_\(UUID().uuidString).tar.gz")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await downloadFile(
            from: downloadURL,
            to: tempURL,
            progressHandler: { progress in
                // Download is 0-80% of overall progress
                Task { @MainActor in progressHandler(progress * 0.8) }
            },
            bytesHandler: { [weak self] bytesDownloaded, _ in
                self?.modelBytesDownloaded[modelId] = bytesDownloaded
            }
        )

        logger.info("Download complete, extracting \(modelId)...")
        await progressHandler(0.8)

        // Extract using the SDK's extraction service
        let extractionService = DefaultExtractionService()
        let artifactType = ModelArtifactType.archive(
            .tarGz, structure: .nestedDirectory, expectedFiles: .none
        )
        _ = try await extractionService.extract(
            archiveURL: tempURL,
            to: destinationFolder,
            artifactType: artifactType,
            progressHandler: { extractionProgress in
                // Extraction is 80-100% of overall progress
                Task { @MainActor in progressHandler(0.8 + extractionProgress * 0.2) }
            }
        )

        logger.info("Model extracted successfully: \(modelId) → \(destinationFolder.path)")
        await progressHandler(1.0)
    }

    /// Download a file from a URL to a local path with progress reporting.
    /// - Parameters:
    ///   - progressHandler: Reports fraction (0.0–1.0)
    ///   - bytesHandler: Reports (bytesDownloaded, totalBytes)
    private func downloadFile(
        from url: URL,
        to destination: URL,
        progressHandler: @escaping (Double) -> Void,
        bytesHandler: (@MainActor (Int64, Int64) -> Void)? = nil
    ) async throws {
        let delegate = DownloadProgressDelegate(
            progressHandler: progressHandler,
            bytesHandler: bytesHandler
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (tempURL, response) = try await session.download(from: url, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw RunAnywhereServiceError.downloadFailed("HTTP \(code) downloading \(url)")
        }

        // Move from system temp to our desired location
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private func loadSTTModelSafe(_ modelId: String) async throws {
        guard let modelInfo = registeredModels[modelId] else {
            throw RunAnywhereServiceError.modelNotFound(modelId)
        }

        let modelPath: URL
        if modelInfo.framework == .whisperKitCoreML {
            modelPath = try resolveWhisperKitModelPath(modelId: modelId, framework: modelInfo.framework)
        } else {
            modelPath = try resolveONNXModelPath(modelId: modelId, framework: modelInfo.framework)
        }

        logger.info("Loading STT model \(modelId) (framework: \(modelInfo.framework.displayName)) from \(modelPath.path)")

        try await CppBridge.STT.shared.loadModel(
            modelPath.path,
            modelId: modelId,
            modelName: modelInfo.name,
            framework: modelInfo.framework.toCFramework()
        )
    }

    private func loadTTSVoiceSafe(_ voiceId: String) async throws {
        guard let modelInfo = registeredModels[voiceId] else {
            throw RunAnywhereServiceError.modelNotFound(voiceId)
        }

        let voicePath = try resolveONNXModelPath(
            modelId: voiceId, framework: modelInfo.framework
        )

        try await CppBridge.TTS.shared.loadVoice(
            voicePath.path,
            voiceId: voiceId,
            voiceName: modelInfo.name
        )
    }

    // MARK: - Model Path Resolution

    /// Resolve path for ONNX/Sherpa models (looks for .onnx files or tokens.txt)
    private func resolveONNXModelPath(modelId: String, framework: InferenceFramework) throws -> URL {
        let modelFolder = try CppBridge.ModelPaths.getModelFolder(
            modelId: modelId, framework: framework
        )
        return resolveModelDir(modelFolder, modelId: modelId, check: hasONNXModelFiles)
    }

    /// Resolve path for WhisperKit CoreML models (looks for .mlmodelc bundles)
    private func resolveWhisperKitModelPath(modelId: String, framework: InferenceFramework) throws -> URL {
        let modelFolder = try CppBridge.ModelPaths.getModelFolder(
            modelId: modelId, framework: framework
        )
        return resolveModelDir(modelFolder, modelId: modelId, check: hasWhisperKitModelFiles)
    }

    /// Generic directory resolver: checks nested dir named after modelId, then root, then any subdirectory.
    private func resolveModelDir(_ modelFolder: URL, modelId: String, check: (URL) -> Bool) -> URL {
        let nestedFolder = modelFolder.appendingPathComponent(modelId)
        if FileManager.default.fileExists(atPath: nestedFolder.path) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: nestedFolder.path, isDirectory: &isDir),
               isDir.boolValue, check(nestedFolder) {
                return nestedFolder
            }
        }

        if check(modelFolder) {
            return modelFolder
        }

        if let contents = try? FileManager.default.contentsOfDirectory(
            at: modelFolder, includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for item in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir),
                   isDir.boolValue, check(item) {
                    return item
                }
            }
        }

        return modelFolder
    }

    // MARK: - Model File Detection

    private func hasONNXModelFiles(at directory: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return false }
        return contents.contains { $0.pathExtension.lowercased() == "onnx" }
            || contents.contains { $0.lastPathComponent == "tokens.txt" }
    }

    private func hasWhisperKitModelFiles(at directory: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return false }
        // WhisperKit expects directories like AudioEncoder.mlmodelc, TextDecoder.mlmodelc
        return contents.contains { $0.pathExtension == "mlmodelc" }
    }

    /// Check if a model (ONNX or WhisperKit) has files on disk.
    private func hasModelFiles(at directory: URL) -> Bool {
        hasONNXModelFiles(at: directory) || hasWhisperKitModelFiles(at: directory)
    }
}

// MARK: - Errors

enum RunAnywhereServiceError: LocalizedError {
    case modelNotFound(String)
    case modelNotDownloaded(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let id):
            return "Model '\(id)' not found in local cache"
        case .modelNotDownloaded(let id):
            return "Model '\(id)' is not downloaded"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        }
    }
}

// MARK: - URLSession Download Progress Delegate

/// Tracks download progress via URLSessionDownloadDelegate.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Double) -> Void
    let bytesHandler: (@MainActor (Int64, Int64) -> Void)?

    init(
        progressHandler: @escaping (Double) -> Void,
        bytesHandler: (@MainActor (Int64, Int64) -> Void)? = nil
    ) {
        self.progressHandler = progressHandler
        self.bytesHandler = bytesHandler
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(min(progress, 1.0))
        if let bytesHandler {
            Task { @MainActor in
                bytesHandler(totalBytesWritten, totalBytesExpectedToWrite)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Required by protocol; actual file handling done in the async download call
    }
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
