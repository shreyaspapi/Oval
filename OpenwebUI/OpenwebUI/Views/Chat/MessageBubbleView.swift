import SwiftUI

/// A single message matching Open WebUI's bubble style.
/// User messages: right-aligned in bg-gray-850 bubble with Liquid Glass.
/// Assistant messages: left-aligned with avatar, no bubble.
struct MessageBubbleView: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var isLastAssistant: Bool = false

    // Callbacks for message actions
    var onEdit: ((String, String, Bool) -> Void)?       // (messageId, newContent, resubmit)
    var onRegenerate: ((String) -> Void)?                // (messageId)
    var onSpeak: ((String, String) -> Void)?             // (content, messageId)
    var onStopSpeaking: (() -> Void)?
    var isSpeakingThis: Bool = false

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == "user" {
                Spacer(minLength: 80)
                userMessage
            } else {
                assistantMessage
                Spacer(minLength: 80)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - User Message

    private var userMessage: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Attached images
            if let images = message.images, !images.isEmpty {
                imageGrid(images)
            }

            // Attached files
            if let files = message.files, !files.isEmpty {
                fileList(files)
            }

            // Text content (or edit mode)
            if isEditing {
                editView
            } else if !message.content.isEmpty {
                Text(message.content)
                    .font(AppFont.body())
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColors.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .glassEffect(
                        .regular.tint(AppColors.userBubbleGlass.opacity(0.4)),
                        in: .rect(cornerRadius: 18)
                    )
            }

            // Action buttons for user messages
            if !isEditing && !isStreaming {
                HStack(spacing: 4) {
                    // Edit button
                    ActionButton(icon: "pencil", help: "Edit message") {
                        editText = message.content
                        isEditing = true
                    }
                    CopyButton(text: message.content)
                }
            }
        }
        .contextMenu {
            Button("Copy") {
                copyToClipboard(message.content)
            }
            if onEdit != nil {
                Button("Edit") {
                    editText = message.content
                    isEditing = true
                }
            }
        }
    }

    // MARK: - Edit View

    private var editView: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $editText)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 200)
                .padding(8)
                .background(AppColors.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.borderColor, lineWidth: 1)
                )

            HStack(spacing: 8) {
                Button("Cancel") {
                    isEditing = false
                    editText = ""
                }
                .buttonStyle(.plain)
                .font(AppFont.body(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.hoverBg)
                .clipShape(Capsule())

                Button("Save") {
                    let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onEdit?(message.id, trimmed, false)
                    }
                    isEditing = false
                    editText = ""
                }
                .buttonStyle(.plain)
                .font(AppFont.body(size: 13))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.hoverBg)
                .clipShape(Capsule())

                Button("Save & Submit") {
                    let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onEdit?(message.id, trimmed, true)
                    }
                    isEditing = false
                    editText = ""
                }
                .buttonStyle(.plain)
                .font(AppFont.body(size: 13).weight(.medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.accentBlue)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Assistant Message

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(AppColors.avatarBg)
                    .frame(width: 30, height: 30)
                Text("O")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.avatarText)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                // Model name
                if let model = message.model {
                    Text(model)
                        .font(AppFont.caption())
                        .foregroundStyle(AppColors.textTertiary)
                }

                // Tool calls
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(toolCalls) { tc in
                            ToolCallView(toolCall: tc)
                        }
                    }
                }

                // Reasoning/thinking blocks (parsed from content)
                let parsed = parseReasoningBlocks(message.content)
                if !parsed.reasoning.isEmpty {
                    ForEach(Array(parsed.reasoning.enumerated()), id: \.offset) { _, block in
                        ReasoningBlockView(block: block, isStreaming: isStreaming)
                    }
                }

                // Message content (with reasoning stripped)
                if parsed.visibleContent.isEmpty && isStreaming {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(AppColors.textTertiary)
                                .frame(width: 6, height: 6)
                                .opacity(0.6)
                        }
                    }
                    .padding(.top, 4)
                } else if !parsed.visibleContent.isEmpty {
                    MarkdownTextView(content: parsed.visibleContent)
                }

                // Action buttons (copy, regenerate, play)
                if !isStreaming && !message.content.isEmpty {
                    HStack(spacing: 4) {
                        CopyButton(text: message.content)

                        // Play / Stop TTS
                        if isSpeakingThis {
                            ActionButton(icon: "stop.fill", help: "Stop speaking") {
                                onStopSpeaking?()
                            }
                        } else {
                            ActionButton(icon: "speaker.wave.2", help: "Read aloud") {
                                onSpeak?(message.content, message.id)
                            }
                        }

                        // Regenerate (only on last assistant message)
                        if isLastAssistant {
                            ActionButton(icon: "arrow.counterclockwise", help: "Regenerate response") {
                                onRegenerate?(message.id)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .contextMenu {
                Button("Copy Message") {
                    copyToClipboard(message.content)
                }
                if onSpeak != nil {
                    Button(isSpeakingThis ? "Stop Speaking" : "Read Aloud") {
                        if isSpeakingThis {
                            onStopSpeaking?()
                        } else {
                            onSpeak?(message.content, message.id)
                        }
                    }
                }
                if isLastAssistant, onRegenerate != nil {
                    Button("Regenerate Response") {
                        onRegenerate?(message.id)
                    }
                }
            }
        }
    }

    // MARK: - Reasoning Parser

    struct ReasoningBlock {
        let summary: String
        let content: String
        let duration: String?
        let isDone: Bool
    }

    struct ParsedContent {
        let reasoning: [ReasoningBlock]
        let visibleContent: String
    }

    /// Parse <details type="reasoning">...</details> blocks from the message content.
    private func parseReasoningBlocks(_ content: String) -> ParsedContent {
        var blocks: [ReasoningBlock] = []
        var visible = content

        // Regex to match <details type="reasoning" ...>...<summary>...</summary>...\n</details>
        let pattern = #"<details[^>]*type="reasoning"([^>]*)>([\s\S]*?)</details>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ParsedContent(reasoning: [], visibleContent: content)
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

        for match in matches.reversed() {
            let fullRange = match.range
            let attrsRange = match.range(at: 1)
            let innerRange = match.range(at: 2)

            let attrs = nsContent.substring(with: attrsRange)
            let inner = nsContent.substring(with: innerRange)

            // Extract done and duration from attributes
            let isDone = attrs.contains("done=\"true\"") || !isStreaming
            var duration: String? = nil
            if let durationMatch = try? NSRegularExpression(pattern: #"duration="(\d+(?:\.\d+)?)"#).firstMatch(in: attrs, range: NSRange(location: 0, length: (attrs as NSString).length)) {
                duration = (attrs as NSString).substring(with: durationMatch.range(at: 1))
            }

            // Extract summary
            var summary = "Thinking"
            let summaryPattern = #"<summary>(.*?)</summary>"#
            if let summaryRegex = try? NSRegularExpression(pattern: summaryPattern),
               let summaryMatch = summaryRegex.firstMatch(in: inner, range: NSRange(location: 0, length: (inner as NSString).length)) {
                summary = (inner as NSString).substring(with: summaryMatch.range(at: 1))
            }

            // Strip the summary tag from inner content
            var reasoningContent = inner
            if let summaryRange = reasoningContent.range(of: #"<summary>.*?</summary>"#, options: .regularExpression) {
                reasoningContent.removeSubrange(summaryRange)
            }
            reasoningContent = reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)

            blocks.insert(ReasoningBlock(
                summary: summary,
                content: reasoningContent,
                duration: duration,
                isDone: isDone
            ), at: 0)

            // Remove from visible content
            visible = (visible as NSString).replacingCharacters(in: fullRange, with: "")
        }

        // Also handle unclosed reasoning blocks (still streaming)
        let unclosedPattern = #"<details[^>]*type="reasoning"([^>]*)>([\s\S]*?)$"#
        if let unclosedRegex = try? NSRegularExpression(pattern: unclosedPattern),
           let match = unclosedRegex.firstMatch(in: visible, range: NSRange(location: 0, length: (visible as NSString).length)) {
            let innerRange = match.range(at: 2)
            let inner = (visible as NSString).substring(with: innerRange)

            var reasoningContent = inner
            if let summaryRange = reasoningContent.range(of: #"<summary>.*?</summary>"#, options: .regularExpression) {
                reasoningContent.removeSubrange(summaryRange)
            }
            reasoningContent = reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)

            blocks.append(ReasoningBlock(
                summary: "Thinking",
                content: reasoningContent,
                duration: nil,
                isDone: false
            ))

            visible = (visible as NSString).replacingCharacters(in: match.range, with: "")
        }

        visible = visible.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedContent(reasoning: blocks, visibleContent: visible)
    }

    // MARK: - Image Grid

    @ViewBuilder
    private func imageGrid(_ imageURIs: [String]) -> some View {
        let columns = imageURIs.count == 1 ? 1 : 2
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 4), count: columns)

        LazyVGrid(columns: gridItems, spacing: 4) {
            ForEach(Array(imageURIs.enumerated()), id: \.offset) { _, uri in
                if let nsImage = imageFromDataURI(uri) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: imageURIs.count == 1 ? 320 : 160)
                        .frame(maxHeight: imageURIs.count == 1 ? 280 : 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - File List

    @ViewBuilder
    private func fileList(_ files: [ChatFileRef]) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(files) { file in
                HStack(spacing: 8) {
                    Image(systemName: iconForMIME(file.type))
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name)
                            .font(AppFont.body(size: 13))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        Text(formatFileSize(file.size))
                            .font(AppFont.caption(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.fileAttachmentBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Helpers

    private func imageFromDataURI(_ uri: String) -> NSImage? {
        guard let commaIndex = uri.firstIndex(of: ",") else { return nil }
        let base64String = String(uri[uri.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64String) else { return nil }
        return NSImage(data: data)
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

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Reasoning Block View

/// Collapsible reasoning/thinking block, matching Open WebUI's style.
/// Shows "Thinking..." with spinner while streaming, "Thought for N seconds" when done.
private struct ReasoningBlockView: View {
    let block: MessageBubbleView.ReasoningBlock
    var isStreaming: Bool = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header button
            Button {
                if !block.content.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if !block.isDone {
                        // Streaming: animated spinner
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Text(headerText)
                        .font(AppFont.caption(size: 12).weight(.medium))
                        .foregroundStyle(AppColors.textSecondary)

                    if !block.content.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable reasoning content
            if isExpanded && !block.content.isEmpty {
                Divider()
                    .padding(.horizontal, 10)

                Text(block.content)
                    .font(AppFont.body(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(AppColors.fileAttachmentBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.borderColor.opacity(0.5), lineWidth: 0.5)
        )
    }

    private var headerText: String {
        if !block.isDone {
            return "Thinking..."
        }
        if let duration = block.duration, let seconds = Double(duration) {
            if seconds < 1 {
                return "Thought for less than a second"
            } else if seconds < 60 {
                return "Thought for \(Int(seconds)) second\(Int(seconds) == 1 ? "" : "s")"
            } else {
                let minutes = Int(seconds) / 60
                return "Thought for \(minutes) minute\(minutes == 1 ? "" : "s")"
            }
        }
        return "Thought"
    }
}

// MARK: - Tool Call View

private struct ToolCallView: View {
    let toolCall: ToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.accentBlue)
                    Text(toolCall.function.name)
                        .font(AppFont.caption(size: 12).weight(.medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(formatArguments(toolCall.function.arguments))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .padding(.top, 2)
            }
        }
        .background(AppColors.fileAttachmentBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatArguments(_ args: String) -> String {
        guard let data = args.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return args }
        return str
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Copy Button

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12))
                .foregroundStyle(copied ? AppColors.green400 : AppColors.textTertiary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy message")
    }
}
