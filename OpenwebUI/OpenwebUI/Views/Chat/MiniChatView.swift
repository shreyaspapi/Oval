import SwiftUI

/// Mini chat interface matching ChatGPT's quick chat style.
///
/// Two modes:
/// - **Compact** (no messages): Just the input bar with "Ask anything" placeholder
///   and action buttons (attach, web search, model selector, mic, send)
/// - **Expanded** (has messages): Close/copy/new buttons at top, messages area,
///   and the same input bar at bottom
struct MiniChatView: View {
    @Bindable var appState: AppState

    @FocusState private var isInputFocused: Bool
    @State private var showModelPicker = false

    private var hasMessages: Bool {
        !appState.miniChatMessages.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasMessages {
                expandedContent
            } else {
                compactContent
            }
        }
        .background(Color(hex: "#1a1a1a"))
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - Compact Mode (input only)

    private var compactContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            miniInputCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Expanded Mode (toolbar + messages + input)

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Top toolbar
            expandedToolbar
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)

            // Messages
            miniMessageList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Input card at bottom
            miniInputCard
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .padding(.top, 4)
        }
    }

    // MARK: - Expanded Toolbar

    private var expandedToolbar: some View {
        HStack(spacing: 12) {
            // Close button
            Button {
                appState.miniChatWindowManager.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: "#666666"))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")

            Spacer()

            // Copy last response
            Button {
                appState.copyLastAssistantMessage()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#999999"))
            }
            .buttonStyle(.plain)
            .help("Copy last response")
            .disabled(appState.miniChatMessages.last(where: { $0.role == "assistant" }) == nil)

            // New chat
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.newMiniChat()
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#999999"))
            }
            .buttonStyle(.plain)
            .help("New chat")
        }
    }

    // MARK: - Input Card (shared between compact and expanded)

    private var miniInputCard: some View {
        VStack(spacing: 0) {
            // Text field row
            ZStack(alignment: .topLeading) {
                if appState.miniMessageInput.isEmpty {
                    Text("Ask anything")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "#666666"))
                        .padding(.leading, 4)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }

                MiniChatTextField(
                    text: $appState.miniMessageInput,
                    onSubmit: {
                        sendAndExpand()
                    }
                )
                .focused($isInputFocused)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Action buttons row
            HStack(spacing: 2) {
                // Attach button
                Button {
                    // TODO: file picker for mini chat
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "#999999"))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("Attach")

                // Web search toggle
                Button {
                    appState.isWebSearchEnabled.toggle()
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(appState.isWebSearchEnabled ? Color.white : Color(hex: "#999999"))
                        .frame(width: 30, height: 30)
                        .background(appState.isWebSearchEnabled ? Color(hex: "#3b82f6").opacity(0.7) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Web search")

                // Model selector
                Button {
                    showModelPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 13, weight: .medium))
                        Text(shortModelName)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "#999999"))
                    .padding(.horizontal, 6)
                    .frame(height: 30)
                }
                .buttonStyle(.plain)
                .help("Select model")
                .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                    miniModelPicker
                }

                Spacer()

                // Mic button
                Button {
                    if appState.speechManager.isListening {
                        appState.speechManager.stopListening()
                        let text = appState.speechManager.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            if appState.miniMessageInput.isEmpty {
                                appState.miniMessageInput = text
                            } else {
                                appState.miniMessageInput += " " + text
                            }
                        }
                    } else {
                        appState.speechManager.startListening()
                    }
                } label: {
                    Image(systemName: appState.speechManager.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(appState.speechManager.isListening ? Color.white : Color(hex: "#999999"))
                        .frame(width: 30, height: 30)
                        .background(appState.speechManager.isListening ? Color.red.opacity(0.7) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Voice input")

                // Send / Stop button
                Button {
                    if appState.isMiniStreaming {
                        appState.stopMiniStreaming()
                    } else {
                        sendAndExpand()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(miniCanSend ? Color.white : Color(hex: "#444444"))
                            .frame(width: 30, height: 30)

                        if appState.isMiniStreaming {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: "#1a1a1a"))
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(miniCanSend ? Color(hex: "#1a1a1a") : Color(hex: "#666666"))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!miniCanSend && !appState.isMiniStreaming)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(Color(hex: "#2a2a2a"))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(hex: "#3a3a3a"), lineWidth: 0.5)
        )
    }

    // MARK: - Model Picker Popover

    private var miniModelPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.models.isEmpty {
                Text("No models available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(appState.models) { model in
                            let isSelected = model.id == appState.selectedModel?.id
                            Button {
                                appState.selectedModel = model
                                showModelPicker = false
                            } label: {
                                HStack {
                                    Text(model.displayName)
                                        .font(.callout)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundStyle(AppColors.accentBlue)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isSelected ? AppColors.selectedBg : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 280)
    }

    // MARK: - Message List

    private var miniMessageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.miniChatMessages, id: \.id) { message in
                        MiniMessageRow(
                            message: message,
                            isStreaming: appState.isMiniStreaming
                                && message.id == appState.miniChatMessages.last?.id
                                && message.role == "assistant"
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: appState.miniChatMessages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: appState.miniStreamingContent) {
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastId = appState.miniChatMessages.last?.id {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    // MARK: - Helpers

    private var miniCanSend: Bool {
        let hasText = !appState.miniMessageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText && !appState.isMiniStreaming && appState.selectedModel != nil && appState.serverReachable
    }

    /// Short model name for the button label (e.g. "4o" from "gpt-4o", "5.2" from "chatgpt-5.2")
    private var shortModelName: String {
        guard let model = appState.selectedModel else { return "Model" }
        let name = model.displayName
        // Try to extract a short version
        if let range = name.range(of: #"\d+[\.\d]*"#, options: .regularExpression) {
            return String(name[range])
        }
        // Fallback: last component after - or /
        let parts = name.split(separator: "/").last.map(String.init) ?? name
        let segments = parts.split(separator: "-")
        if segments.count > 1 {
            return String(segments.last ?? Substring(name))
        }
        // If name is short enough, use it
        if name.count <= 12 { return name }
        return String(name.prefix(10))
    }

    private func sendAndExpand() {
        let wasEmpty = appState.miniChatMessages.isEmpty
        Task {
            await appState.sendMiniMessage()
        }
        if wasEmpty {
            // Animate panel expansion
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appState.miniChatWindowManager.expandToFullSize()
            }
        }
    }
}

// MARK: - Mini Message Row

/// Compact message row for the mini chat. User messages right-aligned, assistant left-aligned.
struct MiniMessageRow: View {
    let message: ChatMessage
    var isStreaming: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == "user" {
                Spacer(minLength: 60)
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#e4e4e4"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#333333"))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if message.content.isEmpty && isStreaming {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 16, height: 16)
                            Text("Thinking...")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#999999"))
                        }
                    } else {
                        MarkdownTextView(content: message.content)
                    }

                    // Action buttons under assistant message (copy, etc.)
                    if !message.content.isEmpty && !isStreaming {
                        HStack(spacing: 12) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: "#666666"))
                            }
                            .buttonStyle(.plain)
                            .help("Copy")
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 60)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mini Chat Text Field (NSTextField-based for focus handling in NSPanel)

struct MiniChatTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 15)
        field.textColor = NSColor(hex: "#e4e4e4")
        field.focusRingType = .none
        field.placeholderString = ""
        field.delegate = context.coordinator
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MiniChatTextField

        init(_ parent: MiniChatTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
