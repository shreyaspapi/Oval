import SwiftUI

/// Settings tab for managing RunAnywhere on-device voice models.
/// Users can browse, download, and select STT and TTS models.
struct VoiceModelSettingsView: View {
    private let raService = RunAnywhereService.shared

    var body: some View {
        Form {
            // Status
            Section(String(localized: "settings.voice.engine")) {
                LabeledContent(String(localized: "settings.voice.engineName")) {
                    Text(String(localized: "settings.voice.engineValue"))
                        .foregroundStyle(.secondary)
                }
                LabeledContent(String(localized: "settings.voice.status")) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(raService.isVoiceReady ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(raService.isVoiceReady
                             ? String(localized: "settings.voice.statusReady")
                             : (raService.isSDKReady
                                ? String(localized: "settings.voice.statusModelsNeeded")
                                : String(localized: "settings.voice.statusInitializing")))
                    }
                }
            }

            // STT Model Selection
            Section(String(localized: "settings.voice.stt")) {
                ForEach(RunAnywhereService.sttCatalog) { entry in
                    modelRow(entry: entry, isSelected: entry.id == raService.selectedSTTModelId) {
                        Task { await raService.selectSTTModel(entry.id) }
                    }
                }
            }

            // TTS Voice Selection
            Section(String(localized: "settings.voice.tts")) {
                ForEach(RunAnywhereService.ttsCatalog) { entry in
                    modelRow(entry: entry, isSelected: entry.id == raService.selectedTTSModelId) {
                        Task { await raService.selectTTSModel(entry.id) }
                    }
                }
            }

            // Error
            if let error = raService.error {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Info
            Section(String(localized: "settings.voice.about")) {
                Text(String(localized: "settings.voice.aboutText"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Model Row

    private func modelRow(entry: RAModelCatalogEntry, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        // While the SDK is still checking states, use whatever we pre-loaded
        // from disk (which is accurate for downloaded/notDownloaded). The
        // isCheckingModelStates flag prevents flashing wrong UI.
        let state = raService.modelStates[entry.id] ?? .notDownloaded

        return HStack(spacing: 12) {
            // Selection radio
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? .blue : .secondary)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.system(size: 13, weight: .medium))

                    Text(entry.language)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())

                    Text(entry.quality)
                        .font(.system(size: 10))
                        .foregroundStyle(qualityColor(entry.quality))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(qualityColor(entry.quality).opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(entry.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Label(entry.size, systemImage: "arrow.down.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Action / State
            modelAction(entry: entry, state: state, isSelected: isSelected, onSelect: onSelect)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            // If already downloaded, selecting it is enough
            if state == .downloaded || state == .loaded {
                onSelect()
            }
        }
    }

    @ViewBuilder
    private func modelAction(entry: RAModelCatalogEntry, state: RAModelState, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        switch state {
        case .loaded:
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text(String(localized: "settings.voice.stateReady"))
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        case .downloaded:
            if isSelected {
                HStack(spacing: 4) {
                    Circle().fill(.blue).frame(width: 6, height: 6)
                    Text(String(localized: "settings.voice.stateDownloaded"))
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            } else {
                Button(String(localized: "settings.voice.stateSelect")) {
                    onSelect()
                }
                .controlSize(.small)
            }

        case .downloading:
            let progress = raService.modelDownloadProgress[entry.id] ?? 0
            let bytesDownloaded = raService.modelBytesDownloaded[entry.id] ?? 0
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 100)
                HStack(spacing: 4) {
                    if progress > 0 && progress < 0.8 {
                        // Downloading phase (0–80% of overall)
                        Text(String(format: String(localized: "settings.voice.stateDownloaded.label"), formatMB(bytesDownloaded)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else if progress >= 0.8 {
                        ProgressView()
                            .controlSize(.mini)
                        Text(String(localized: "settings.voice.stateExtracting"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                        Text(String(localized: "settings.voice.stateStarting"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .loading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(String(localized: "settings.voice.stateLoading"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .notDownloaded:
            // While SDK is still initializing, show a checking indicator
            // instead of a premature "Download" button
            if raService.isCheckingModelStates && raService.isSDKReady == false {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(String(localized: "settings.voice.stateChecking"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(String(localized: "settings.voice.stateDownload")) {
                    Task {
                        await raService.downloadModel(id: entry.id)
                        // Auto-select after download
                        if entry.category == .stt {
                            await raService.selectSTTModel(entry.id)
                        } else {
                            await raService.selectTTSModel(entry.id)
                        }
                    }
                }
                .controlSize(.small)
            }

        case .error(let msg):
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                Button(String(localized: "settings.voice.retry")) {
                    // Reset state so download/load can be attempted again
                    raService.modelStates[entry.id] = .notDownloaded
                    raService.error = nil
                    if entry.id == raService.selectedSTTModelId { raService.sttModelState = .notDownloaded }
                    if entry.id == raService.selectedTTSModelId { raService.ttsModelState = .notDownloaded }
                    Task {
                        await raService.downloadModel(id: entry.id)
                        if entry.category == .stt {
                            await raService.selectSTTModel(entry.id)
                        } else {
                            await raService.selectTTSModel(entry.id)
                        }
                    }
                }
                .controlSize(.mini)
            }
        }
    }

    private func formatMB(_ bytes: Int64) -> String {
        if bytes < 1_000_000 {
            return "\(bytes / 1_000) KB"
        } else {
            let mb = Double(bytes) / 1_000_000.0
            return String(format: "%.1f MB", mb)
        }
    }

    private func qualityColor(_ quality: String) -> Color {
        switch quality {
        case "Best": return .green
        case "Better": return .blue
        case "Good": return .orange
        default: return .secondary
        }
    }
}
