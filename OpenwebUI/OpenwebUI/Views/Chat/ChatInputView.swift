import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Chat input bar with file/image attachment support.
/// Uses a custom NSTextView that intercepts Cmd+V paste for images/files.
struct ChatInputView: View {
    @Bindable var appState: AppState

    @FocusState private var isInputFocused: Bool
    @State private var pulsingDot = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Main input area
                VStack(spacing: 0) {
                    // Attachment previews (shown above text when attachments are pending)
                    if !appState.pendingAttachments.isEmpty {
                        AttachmentPreviewRow(appState: appState)
                            .padding(.bottom, 6)
                    }

                    // Live transcription banner
                    if appState.speechManager.isListening {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .opacity(pulsingDot ? 0.4 : 1.0)
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsingDot)
                                .onAppear { pulsingDot = true }
                                .onDisappear { pulsingDot = false }

                            Text(appState.speechManager.transcript.isEmpty ? String(localized: "chatInput.listening") : appState.speechManager.transcript)
                                .font(AppFont.body(size: 13))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(2)
                                .truncationMode(.head)

                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 6)
                        .transition(.opacity)
                    }

                    // Speech error
                    if let speechError = appState.speechManager.error {
                        Text(speechError)
                            .font(AppFont.caption(size: 11))
                            .foregroundStyle(AppColors.red400)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                    }

                    // Text area with paste interception
                    ZStack(alignment: .topLeading) {
                        if appState.messageInput.isEmpty && appState.pendingAttachments.isEmpty && !appState.speechManager.isListening {
                            Text("chatInput.placeholder")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.textPlaceholder)
                                .padding(.top, 1)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }

                        PasteAwareTextEditor(
                            text: $appState.messageInput,
                            onPasteFile: { attachment in
                                appState.addAttachment(attachment)
                            },
                            onReturnKey: {
                                Task { await appState.sendMessage() }
                            }
                        )
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)

                    // Bottom row: action buttons
                    HStack(spacing: 4) {
                        // Attach file button
                        Button {
                            openFilePicker()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(AppColors.inputActionBg.opacity(0.6))
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "chatInput.attachHelp"))

                        // Web search toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appState.isWebSearchEnabled.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.system(size: 15, weight: .medium))
                        if appState.isWebSearchEnabled {
                                Text("chatInput.searchLabel")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                            .foregroundStyle(appState.isWebSearchEnabled ? Color.white : AppColors.textSecondary)
                            .padding(.horizontal, appState.isWebSearchEnabled ? 10 : 0)
                            .frame(minWidth: 32, minHeight: 32)
                            .background(appState.isWebSearchEnabled ? AppColors.webSearchActiveBg.opacity(0.7) : AppColors.inputActionBg.opacity(0.6))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(appState.isWebSearchEnabled ? String(localized: "chatInput.webSearchDisable") : String(localized: "chatInput.webSearchEnable"))

                        // Integrations: tools + model features (image gen, code interpreter, memory)
                        IntegrationsButton(appState: appState)

                        // Speech-to-text toggle
                        Button {
                            if appState.speechManager.isListening {
                                appState.speechManager.stopListening()
                                // Append transcript to message input
                                let text = appState.speechManager.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !text.isEmpty {
                                    if appState.messageInput.isEmpty {
                                        appState.messageInput = text
                                    } else {
                                        appState.messageInput += " " + text
                                    }
                                }
                            } else {
                                appState.speechManager.startListening()
                            }
                        } label: {
                            Image(systemName: appState.speechManager.isListening ? "mic.fill" : "mic")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(appState.speechManager.isListening ? Color.white : AppColors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(appState.speechManager.isListening ? Color.red.opacity(0.7) : AppColors.inputActionBg.opacity(0.6))
                                .clipShape(Circle())
                                .contentShape(Circle())
                                .animation(.easeInOut(duration: 0.15), value: appState.speechManager.isListening)
                        }
                        .buttonStyle(.plain)
                        .help(appState.speechManager.isListening ? String(localized: "chatInput.stopListening") : String(localized: "chatInput.speechToText"))

                        // Voice conversation mode (on-device STT/TTS)
                        Button {
                            appState.setVoiceModeActive(true)
                        } label: {
                            Image(systemName: "waveform")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(AppColors.inputActionBg.opacity(0.6))
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "chatInput.voiceMode"))

                        // Live transcription (realtime captions)
                        Button {
                            appState.setRealtimeTranscriptionActive(!appState.isRealtimeTranscriptionActive)
                        } label: {
                            Image(systemName: appState.isRealtimeTranscriptionActive ? "captions.bubble.fill" : "captions.bubble")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(appState.isRealtimeTranscriptionActive ? Color.white : AppColors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(appState.isRealtimeTranscriptionActive ? AppColors.accentBlue.opacity(0.7) : AppColors.inputActionBg.opacity(0.6))
                                .clipShape(Circle())
                                .contentShape(Circle())
                                .animation(.easeInOut(duration: 0.15), value: appState.isRealtimeTranscriptionActive)
                        }
                        .buttonStyle(.plain)
                        .help(appState.isRealtimeTranscriptionActive ? String(localized: "chatInput.stopLiveTranscription") : String(localized: "chatInput.liveTranscription"))

                        Spacer()

                        // Character hint
                        if appState.messageInput.count > 200 {
                            Text("\(appState.messageInput.count)")
                                .font(AppFont.mono(size: 11))
                                .foregroundStyle(AppColors.textTertiary)
                                .padding(.trailing, 4)
                        }

                        // Send / Stop button
                        Button {
                            if appState.isStreaming {
                                appState.stopStreaming()
                            } else {
                                Task { await appState.sendMessage() }
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(sendButtonColor)
                                    .frame(width: 32, height: 32)

                                if appState.isStreaming {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(AppColors.sendButtonIcon)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(canSend ? AppColors.sendButtonIcon : AppColors.textTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend && !appState.isStreaming)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(
                    .regular.tint(AppColors.inputGlass.opacity(0.3)),
                    in: .rect(cornerRadius: 24)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            isInputFocused ? AppColors.textTertiary : AppColors.borderColor,
                            lineWidth: 1
                        )
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .padding(.top, 8)

            // Footer
            Text("chatInput.disclaimer")
                .font(AppFont.caption(size: 11))
                .foregroundStyle(AppColors.textTertiary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.chatBg)
    }

    private var canSend: Bool {
        let hasText = !appState.messageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !appState.pendingAttachments.isEmpty
        return (hasText || hasAttachments)
            && !appState.isStreaming
            && appState.selectedModel != nil
    }

    private var sendButtonColor: Color {
        if appState.isStreaming {
            return AppColors.sendButtonBg
        }
        return canSend ? AppColors.sendButtonBg : AppColors.sendButtonDisabled
    }

    // MARK: - File Picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .image, .png, .jpeg, .gif, .webP, .svg, .heic,
            .pdf, .plainText, .json, .html,
            .commaSeparatedText, .xml,
            UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
            UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
            .data
        ]
        panel.title = String(localized: "chatInput.attachFilesTitle")
        panel.message = String(localized: "chatInput.attachFilesMessage")

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            addFileFromURL(url)
        }
    }

    private func addFileFromURL(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let fileName = url.lastPathComponent
        let mimeType = mimeTypeForURL(url)
        let isImage = mimeType.hasPrefix("image/")
        let attachment = PendingAttachment(
            fileName: fileName,
            mimeType: mimeType,
            data: data,
            isImage: isImage
        )
        appState.addAttachment(attachment)
    }

    private func mimeTypeForURL(_ url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}

// MARK: - Paste-Aware Text Editor (NSViewRepresentable)

/// A custom NSTextView wrapper that intercepts Cmd+V paste events.
/// When the pasteboard contains images or file URLs, it creates PendingAttachments
/// instead of inserting text. Plain text paste works as normal.
struct PasteAwareTextEditor: View {
    @Binding var text: String
    var onPasteFile: (PendingAttachment) -> Void
    var onReturnKey: () -> Void

    @State private var contentHeight: CGFloat = 24

    var body: some View {
        PasteAwareTextEditorRep(
            text: $text,
            contentHeight: $contentHeight,
            onPasteFile: onPasteFile,
            onReturnKey: onReturnKey
        )
        .frame(height: min(max(contentHeight, 24), 180))
    }
}

private struct PasteAwareTextEditorRep: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    var onPasteFile: (PendingAttachment) -> Void
    var onReturnKey: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PasteInterceptingTextView()

        textView.delegate = context.coordinator
        textView.pasteHandler = { attachment in
            DispatchQueue.main.async {
                onPasteFile(attachment)
            }
        }
        textView.returnHandler = {
            DispatchQueue.main.async {
                onReturnKey()
            }
        }

        // Match the original TextEditor appearance
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = AppColors.nsTextColor
        textView.insertionPointColor = AppColors.nsInsertionPointColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 2
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.updateHeight()
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteAwareTextEditorRep
        weak var textView: PasteInterceptingTextView?

        init(_ parent: PasteAwareTextEditorRep) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight()
        }

        func updateHeight() {
            guard let textView else { return }
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
            let newHeight = usedRect.height + 4 // small padding
            DispatchQueue.main.async {
                self.parent.contentHeight = newHeight
            }
        }
    }
}

/// NSTextView subclass that overrides paste: to intercept images and files.
class PasteInterceptingTextView: NSTextView {
    var pasteHandler: ((PendingAttachment) -> Void)?
    var returnHandler: (() -> Void)?

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general

        // Check for file URLs first
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            var handledFiles = false
            for url in urls {
                if let data = try? Data(contentsOf: url) {
                    let fileName = url.lastPathComponent
                    let mimeType = mimeTypeForURL(url)
                    let isImage = mimeType.hasPrefix("image/")
                    let attachment = PendingAttachment(
                        fileName: fileName,
                        mimeType: mimeType,
                        data: data,
                        isImage: isImage
                    )
                    pasteHandler?(attachment)
                    handledFiles = true
                }
            }
            if handledFiles { return }
        }

        // Check for image data on the pasteboard (e.g. screenshot, copied image)
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in imageTypes {
            if let data = pb.data(forType: type) {
                let isPng = type == .png
                let attachment = PendingAttachment(
                    fileName: isPng ? "pasted-image.png" : "pasted-image.tiff",
                    mimeType: isPng ? "image/png" : "image/tiff",
                    data: data,
                    isImage: true
                )
                pasteHandler?(attachment)
                return
            }
        }

        // No image/file — fall through to normal text paste
        super.paste(sender)
    }

    override func keyDown(with event: NSEvent) {
        // Return without modifiers sends the message
        if event.keyCode == 36 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            returnHandler?()
            return
        }
        super.keyDown(with: event)
    }

    private func mimeTypeForURL(_ url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}

// MARK: - Attachment Preview Row

/// Horizontal scrollable row of attachment thumbnails shown above the text input.
struct AttachmentPreviewRow: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.pendingAttachments) { attachment in
                    AttachmentThumbnail(attachment: attachment) {
                        appState.removeAttachment(attachment.id)
                    }
                }
            }
        }
    }
}

/// A single attachment thumbnail with remove button.
struct AttachmentThumbnail: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if attachment.isImage, let nsImage = NSImage(data: attachment.data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // File icon
                VStack(spacing: 4) {
                    Image(systemName: iconForMIME(attachment.mimeType))
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(attachment.fileName)
                        .font(AppFont.caption(size: 9))
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 64, height: 64)
                .background(AppColors.fileAttachmentBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textSecondary)
                    .background(Circle().fill(AppColors.chatBg))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    private func iconForMIME(_ mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime == "application/pdf" { return "doc.richtext" }
        if mime.contains("spreadsheet") || mime.contains("csv") { return "tablecells" }
        if mime.contains("word") || mime.contains("document") { return "doc.text" }
        if mime.contains("json") { return "curlybraces" }
        if mime.contains("text") || mime.contains("html") { return "doc.plaintext" }
        return "doc"
    }
}

// MARK: - Integrations Button

/// Input-bar control for choosing which server tools and model features are active for the
/// next message. Tools come from `GET /api/v1/tools/` (including MCP servers like Kagi).
/// Feature toggles (image generation, code interpreter, memory) are shown only when the
/// selected model advertises the capability in `info.meta.capabilities`.
private struct IntegrationsButton: View {
    @Bindable var appState: AppState
    @State private var showPopover = false

    private var caps: ModelCapabilities? { appState.selectedModel?.info?.meta?.capabilities }
    private var hasImage: Bool { caps?.image_generation == true }
    private var hasCode: Bool { caps?.code_interpreter == true }
    private var hasMemory: Bool { caps?.memory == true }
    private var hasAnyFeature: Bool { hasImage || hasCode || hasMemory }

    private var activeCount: Int {
        var n = appState.selectedToolIds.count
        if hasImage && appState.isImageGenerationEnabled { n += 1 }
        if hasCode && appState.isCodeInterpreterEnabled { n += 1 }
        if hasMemory && appState.isMemoryEnabled { n += 1 }
        return n
    }
    private var isActive: Bool { activeCount > 0 }

    var body: some View {
        if !appState.availableTools.isEmpty || hasAnyFeature {
            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 14, weight: .medium))
                    if isActive {
                        Text(verbatim: "\(activeCount)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(isActive ? Color.white : AppColors.textSecondary)
                .padding(.horizontal, isActive ? 10 : 0)
                .frame(minWidth: 32, minHeight: 32)
                .background(isActive ? AppColors.webSearchActiveBg.opacity(0.7) : AppColors.inputActionBg.opacity(0.6))
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Tools and features")
            .popover(isPresented: $showPopover, arrowEdge: .top) {
                IntegrationsPopover(appState: appState, hasImage: hasImage, hasCode: hasCode, hasMemory: hasMemory)
            }
        }
    }
}

private struct IntegrationsPopover: View {
    @Bindable var appState: AppState
    let hasImage: Bool
    let hasCode: Bool
    let hasMemory: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if hasImage || hasCode || hasMemory {
                sectionHeader("Features")
                if hasImage {
                    toggleRow("Image generation", systemImage: "photo", isOn: $appState.isImageGenerationEnabled)
                }
                if hasCode {
                    toggleRow("Code interpreter", systemImage: "curlybraces", isOn: $appState.isCodeInterpreterEnabled)
                }
                if hasMemory {
                    toggleRow("Memory", systemImage: "brain", isOn: $appState.isMemoryEnabled)
                }
            }

            if !appState.availableTools.isEmpty {
                if hasImage || hasCode || hasMemory { Divider().padding(.vertical, 4) }
                sectionHeader("Tools")
                ForEach(appState.availableTools) { tool in
                    toolRow(tool)
                }
            }
        }
        .padding(.bottom, 10)
        .frame(width: 300)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 2)
    }

    private func toggleRow(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage).font(.system(size: 13))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private func toolRow(_ tool: OWUITool) -> some View {
        let binding = Binding<Bool>(
            get: { appState.selectedToolIds.contains(tool.id) },
            set: { on in
                if on { appState.selectedToolIds.insert(tool.id) }
                else { appState.selectedToolIds.remove(tool.id) }
            }
        )
        return Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.name).font(.system(size: 13))
                if let d = tool.toolDescription, !d.isEmpty {
                    Text(d)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
}
