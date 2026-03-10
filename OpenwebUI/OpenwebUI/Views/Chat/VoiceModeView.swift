import Combine
import SwiftUI

/// Voice conversation view shown in a floating window.
/// Clean, minimal design using the app's existing theme colors.
struct VoiceModeView: View {
    @Bindable var appState: AppState
    let raService = RunAnywhereService.shared

    @State private var animationPhase: Double = 0
    private let animationTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var vm: VoiceModeManager { appState.voiceModeManager }

    var body: some View {
        ZStack {
            // App theme background
            AppColors.chatBg.ignoresSafeArea()

            // Ambient glow behind the orb
            ambientGlow

            VStack(spacing: 0) {
                // Top bar: close button
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(AppColors.hoverBg)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                }

                Spacer()

                // Central orb
                voiceOrb
                    .frame(width: 160, height: 160)
                    .offset(y: -10)

                Spacer()

                // Status / transcript area
                statusSection

                Spacer().frame(height: 20)

                // Bottom controls
                bottomControls
            }
        }
        .onReceive(animationTimer) { _ in
            animationPhase += 1.0 / 60.0
        }
        .onAppear {
            startSessionIfReady()
        }
        .onDisappear {
            vm.stopSession()
        }
    }

    // MARK: - Orb Color (shifts by state)

    private var orbColor: Color {
        switch vm.sessionState {
        case .listening:     return AppColors.accentBlue
        case .transcribing:  return AppColors.blue600
        case .thinking:      return AppColors.blue600
        case .speaking:      return AppColors.green500
        case .error:         return AppColors.red500
        default:             return AppColors.gray500
        }
    }

    // MARK: - Ambient Glow

    private var ambientGlow: some View {
        let energy = CGFloat(vm.audioLevel)
        let isActive = vm.isActive

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbColor.opacity(isActive ? 0.10 + energy * 0.06 : 0.04), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 120
                    )
                )
                .frame(width: 260, height: 260)
                .blur(radius: 25)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbColor.opacity(isActive ? 0.04 + energy * 0.03 : 0.01), .clear],
                        center: .center,
                        startRadius: 60,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 40)
        }
        .offset(y: -10)
        .animation(.easeInOut(duration: 0.3), value: vm.sessionState)
    }

    // MARK: - Orb

    private var voiceOrb: some View {
        let baseScale: CGFloat = vm.sessionState == .speaking ? 1.04 : 1.0
        let audioScale: CGFloat = CGFloat(vm.audioLevel) * 0.2
        let breathe: CGFloat = sin(animationPhase * 1.0) * 0.015
        let totalScale = baseScale + audioScale + breathe

        return ZStack {
            // Core orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbColor, orbColor.opacity(0.7)],
                        center: UnitPoint(x: 0.4, y: 0.35),
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .scaleEffect(totalScale)

            // Soft inner highlight
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.2), .clear],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 40
                    )
                )
                .scaleEffect(totalScale * 0.85)

            // State icon
            stateIcon
        }
        .animation(.easeInOut(duration: 0.12), value: vm.audioLevel)
        .animation(.easeInOut(duration: 0.4), value: vm.sessionState)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch vm.sessionState {
        case .thinking:
            ProgressView()
                .scaleEffect(0.7)
                .tint(.white)
        case .idle:
            Image(systemName: "mic")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        default:
            EmptyView()
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 8) {
            if !raService.isVoiceReady && !vm.isActive {
                setupPrompt
            } else {
                Text(stateLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)

                if !vm.currentTranscript.isEmpty {
                    Text(vm.currentTranscript)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 24)
                }

                if !vm.assistantResponse.isEmpty {
                    ScrollView {
                        Text(vm.assistantResponse)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxHeight: 80)
                }
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppColors.red500)
                    .padding(.horizontal, 24)
            }
        }
        .frame(minHeight: 50)
    }

    private var stateLabel: String {
        switch vm.sessionState {
        case .idle:         return String(localized: "voiceMode.stateIdle")
        case .listening:    return String(localized: "voiceMode.stateListening")
        case .transcribing: return String(localized: "voiceMode.stateTranscribing")
        case .thinking:     return String(localized: "voiceMode.stateThinking")
        case .speaking:     return String(localized: "voiceMode.stateSpeaking")
        case .error:        return String(localized: "voiceMode.stateError")
        }
    }

    // MARK: - Setup Prompt

    private var setupPrompt: some View {
        VStack(spacing: 12) {
            Text("voiceMode.modelsNeeded")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)

            Text("voiceMode.downloadDescription")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if raService.sttModelState == .downloading || raService.ttsModelState == .downloading {
                VStack(spacing: 4) {
                    ProgressView(value: raService.downloadProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(AppColors.accentBlue)
                        .frame(width: 160)

                    Text("\(Int(raService.downloadProgress * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.textTertiary)
                }
            } else {
                Button {
                    Task {
                        await raService.downloadAndLoadModels()
                        if raService.isVoiceReady {
                            await vm.startSession()
                        }
                    }
                } label: {
                    Text("voiceMode.downloadButton")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.sendButtonIcon)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(AppColors.sendButtonBg)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                modelBadge("STT", state: raService.sttModelState)
                modelBadge("TTS", state: raService.ttsModelState)
            }
        }
    }

    private func modelBadge(_ label: String, state: RAModelState) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(state.isReady ? AppColors.green500 : AppColors.gray500)
                .frame(width: 5, height: 5)
            Text("\(label): \(state.displayName)")
                .font(.system(size: 9))
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 8) {
            Button {
                if vm.isActive {
                    dismiss()
                } else {
                    Task { await vm.startSession() }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(micButtonColor)
                        .frame(width: 50, height: 50)

                    Image(systemName: micButtonIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.plain)

            Text(vm.isActive ? String(localized: "voiceMode.tapToEnd") : String(localized: "voiceMode.tapToStart"))
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.bottom, 24)
    }

    private var micButtonColor: Color {
        switch vm.sessionState {
        case .listening:              return AppColors.red500
        case .transcribing, .thinking: return AppColors.blue600
        case .speaking:               return AppColors.green500
        case .error:                  return AppColors.red500
        default:                      return AppColors.accentBlue
        }
    }

    private var micButtonIcon: String {
        switch vm.sessionState {
        case .idle:                    return "mic"
        case .listening:               return "mic.fill"
        case .transcribing, .thinking: return "waveform"
        case .speaking:                return "speaker.wave.2.fill"
        case .error:                   return "exclamationmark.triangle"
        }
    }

    // MARK: - Helpers

    private func startSessionIfReady() {
        guard raService.isVoiceReady else { return }
        Task { await vm.startSession() }
    }

    private func dismiss() {
        vm.stopSession()
        appState.setVoiceModeActive(false)
    }
}
