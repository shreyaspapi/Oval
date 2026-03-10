import SwiftUI

/// Live captions view displayed in a floating panel.
/// Shows finalized segments + tentative in-progress text with a blinking cursor.
struct RealtimeTranscriptionView: View {
    let appState: AppState

    @State private var showCopied = false

    private var manager: RealtimeTranscriptionManager {
        appState.realtimeTranscriptionManager
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerBar

            // MARK: - Transcript Area
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Finalized segments
                        ForEach(manager.segments) { segment in
                            segmentRow(segment)
                        }

                        // Tentative (in-progress) text
                        if !manager.tentativeText.isEmpty {
                            HStack(alignment: .top, spacing: 0) {
                                Text(manager.tentativeText)
                                    .font(.system(size: 15))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .italic()

                                BlinkingCursor()
                            }
                            .id("tentative")
                        }

                        // Anchor for auto-scroll
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: manager.tentativeText) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: manager.segments.count) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            // MARK: - Footer Controls
            footerBar
        }
        .background(AppColors.chatBg)
        .task {
            if !manager.isActive {
                await manager.loadModel()
                await manager.start()
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Audio level indicator
            if manager.isActive {
                AudioLevelDots(level: manager.audioLevel)
                    .frame(width: 40, height: 16)
            }

            Text("transcription.title")
                .font(AppFont.semibold(size: 13))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            // Current speaker indicator
            if diarizationManager.isEnabled && !diarizationManager.currentSpeaker.isEmpty {
                Text(diarizationManager.currentSpeaker)
                    .font(AppFont.caption(size: 11))
                    .foregroundStyle(speakerColor(for: diarizationManager.currentSpeaker))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(speakerColor(for: diarizationManager.currentSpeaker).opacity(0.12), in: Capsule())
            }

            // Status badge
            if manager.isActive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text("transcription.live")
                        .font(AppFont.caption(size: 10))
                        .foregroundStyle(.red)
                        .fontWeight(.bold)
                }
            } else if !manager.isModelReady {
                Text("transcription.modelNotLoaded")
                    .font(AppFont.caption(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }

            // Close button
            Button {
                appState.transcriptionWindowManager.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(AppColors.hoverBg, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColors.sidebarBg)
    }

    // MARK: - Footer

    private var diarizationManager: SpeakerDiarizationManager {
        appState.speakerDiarizationManager
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            // Start/Stop toggle
            Button {
                if manager.isActive {
                    manager.stop()
                    if diarizationManager.isActive {
                        diarizationManager.stopSession()
                    }
                } else {
                    Task {
                        await manager.start()
                        if diarizationManager.isEnabled, diarizationManager.isModelReady {
                            diarizationManager.startSession()
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: manager.isActive ? "stop.fill" : "mic.fill")
                        .font(.system(size: 12))
                    Text(manager.isActive ? String(localized: "transcription.stop") : String(localized: "transcription.start"))
                        .font(AppFont.semibold(size: 12))
                }
                .foregroundStyle(manager.isActive ? .red : AppColors.accentBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    (manager.isActive ? Color.red : AppColors.accentBlue).opacity(0.12),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)

            // Diarization toggle
            Button {
                Task {
                    if diarizationManager.isEnabled {
                        diarizationManager.isEnabled = false
                        diarizationManager.stopSession()
                    } else {
                        diarizationManager.isEnabled = true
                        if !diarizationManager.isModelReady {
                            await diarizationManager.prepareModels()
                        }
                        if diarizationManager.isModelReady, manager.isActive {
                            diarizationManager.startSession()
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: diarizationManager.isEnabled ? "person.2.fill" : "person.2")
                        .font(.system(size: 11))
                    Text(diarizationManager.isPreparing ? String(localized: "transcription.loading") :
                            diarizationManager.isEnabled ? String(localized: "transcription.speakersOn") : String(localized: "transcription.speakers"))
                        .font(AppFont.caption(size: 11))
                }
                .foregroundStyle(diarizationManager.isEnabled ? Color.white : AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    diarizationManager.isEnabled ? AppColors.emerald600.opacity(0.8) : AppColors.hoverBg,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(diarizationManager.isPreparing)
                    .help(diarizationManager.isEnabled ? String(localized: "transcription.disableSpeakers") : String(localized: "transcription.enableSpeakers"))

            Spacer()

            // Speaker count badge
            if diarizationManager.isEnabled && diarizationManager.speakerCount > 0 {
                Text(diarizationManager.speakerCount == 1 ? String(localized: "transcription.speakerCount.one") : String(format: String(localized: "transcription.speakerCount.other"), diarizationManager.speakerCount))
                    .font(AppFont.caption(size: 10))
                    .foregroundStyle(AppColors.emerald600)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.emerald600.opacity(0.12), in: Capsule())
            }

            // Error message
            if let error = manager.errorMessage ?? diarizationManager.errorMessage {
                Text(error)
                    .font(AppFont.caption(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            // Copy button
            Button {
                let text = manager.fullTranscript
                guard !text.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopied = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                    Text(showCopied ? String(localized: "transcription.copied") : String(localized: "transcription.copy"))
                        .font(AppFont.caption(size: 11))
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.hoverBg, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(manager.fullTranscript.isEmpty)

            // Clear button
            Button {
                manager.clearTranscript()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(AppColors.hoverBg, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(manager.segments.isEmpty && manager.tentativeText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppColors.sidebarBg)
    }

    // MARK: - Segment Row

    private func segmentRow(_ segment: TranscriptionSegment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let speaker = segment.speaker {
                Text(speaker)
                    .font(AppFont.semibold(size: 12))
                    .foregroundStyle(speakerColor(for: speaker))
                    .frame(width: 80, alignment: .trailing)
            }

            Text(segment.text)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
        }
    }

    private func speakerColor(for speaker: String) -> Color {
        let colors: [Color] = [
            AppColors.accentBlue,
            AppColors.emerald600,
            AppColors.red400,
            Color(hex: "#a855f7"),  // purple
            Color(hex: "#f97316"),  // orange
        ]
        let hash = speaker.hashValue
        return colors[abs(hash) % colors.count]
    }
}

// MARK: - Blinking Cursor

struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(AppColors.accentBlue)
            .frame(width: 2, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

// MARK: - Audio Level Dots

/// Small animated dots visualizing current audio input level.
struct AudioLevelDots: View {
    let level: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(dotColor(index: i))
                    .frame(width: 3, height: dotHeight(index: i))
            }
        }
    }

    private func dotHeight(index: Int) -> CGFloat {
        let threshold = Float(index) / 5.0
        let active = level > threshold
        return active ? CGFloat(8 + Int(level * 8)) : 4
    }

    private func dotColor(index: Int) -> Color {
        let threshold = Float(index) / 5.0
        return level > threshold ? AppColors.accentBlue : AppColors.gray400
    }
}
