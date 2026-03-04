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

                            Text(appState.speechManager.transcript.isEmpty ? "Listening..." : appState.speechManager.transcript)
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
                            Text("Send a message")
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
                        .help("Attach file or image")

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
                                    Text("Search")
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
                        .help(appState.isWebSearchEnabled ? "Disable web search" : "Enable web search")

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
                        .help(appState.speechManager.isListening ? "Stop listening" : "Speech to text")

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
                        .help("Voice conversation mode")

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
                        .help(appState.isRealtimeTranscriptionActive ? "Stop live transcription" : "Live transcription (Cmd+Shift+T)")

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
            Text("Oval can make mistakes. Check important info.")
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
        panel.title = "Attach Files"
        panel.message = "Select images or files to send with your message"

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
