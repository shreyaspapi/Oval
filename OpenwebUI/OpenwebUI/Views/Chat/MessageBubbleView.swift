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
    var onFollowUp: ((String) -> Void)?                  // (followUpText) — send as new message
    var isSpeakingThis: Bool = false

    @State private var isEditing = false
    @State private var editText = ""

    /// Merge tool calls from the message model with those parsed from content HTML.
    /// The server embeds tool call results as `<details type="tool_calls">` in the content.
    private var resolvedToolCalls: [ToolCall] {
        var calls = message.toolCalls ?? []
        let contentParsed = AppState.parseToolCallDetails(from: message.content)
        for parsed in contentParsed {
            if let idx = calls.firstIndex(where: { $0.id == parsed.id }) {
                // Update with result/status from content HTML
                if parsed.result != nil || parsed.status == .completed {
                    calls[idx] = parsed
                }
            } else {
                calls.append(parsed)
            }
        }
        return calls
    }

    /// Message content with tool call HTML details stripped (rendered separately above).
    private var strippedContent: String {
        AppState.stripToolCallDetails(from: message.content)
    }

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

                // Search status events (from Socket.IO — web search progress, query chips)
                if let statusHistory = message.statusHistory, !statusHistory.isEmpty {
                    SearchStatusView(statusHistory: statusHistory)
                }

                // Tool calls (from streaming chunks and/or parsed from content HTML)
                let allToolCalls = resolvedToolCalls
                if !allToolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(allToolCalls) { tc in
                            ToolCallView(toolCall: tc, isStreaming: isStreaming)
                        }
                    }
                }

                // Code execution results (from Socket.IO execute:tool events)
                if let codeExecs = message.codeExecutions, !codeExecs.isEmpty {
                    ForEach(codeExecs, id: \.id) { exec in
                        CodeExecutionView(execution: exec)
                    }
                }

                // Reasoning/thinking blocks (parsed from content)
                let parsed = parseReasoningBlocks(strippedContent)
                if !parsed.reasoning.isEmpty {
                    ForEach(Array(parsed.reasoning.enumerated()), id: \.offset) { _, block in
                        ReasoningBlockView(block: block, isStreaming: isStreaming)
                    }
                }

                // Error display (from chat:message:error events)
                if let error = message.messageError, let errorContent = error.content, !errorContent.isEmpty {
                    MessageErrorBanner(content: errorContent)
                }

                // Message content (with reasoning and tool call HTML stripped)
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
                    MarkdownTextView(content: parsed.visibleContent, sources: message.sources)
                }

                // Sources / citations (from Socket.IO source events)
                if let sources = message.sources, !sources.isEmpty {
                    SourcesView(sources: sources)
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

                        // Token usage (subtle inline display)
                        if let usage = message.usage, let total = usage.total_tokens, total > 0 {
                            Text("\(total) tokens")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary.opacity(0.7))
                                .padding(.leading, 4)
                        }
                    }
                    .padding(.top, 4)
                }

                // Follow-up suggestions (tappable chips)
                if let followUps = message.followUps, !followUps.isEmpty, isLastAssistant, !isStreaming {
                    FollowUpChipsView(suggestions: followUps) { text in
                        onFollowUp?(text)
                    }
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
            reasoningContent = Self.cleanReasoningContent(reasoningContent)

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
            reasoningContent = Self.cleanReasoningContent(reasoningContent)

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

    /// Clean reasoning content extracted from `<details type="reasoning">` blocks.
    /// The server may HTML-encode entities (e.g. `&#x27;` for `'`, `&gt;` for `>`)
    /// and wrap lines in blockquotes (`> `). This decodes entities and strips
    /// blockquote markers so the plain text displays correctly.
    private static func cleanReasoningContent(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        // Strip leading blockquote markers ("> " or ">") from each line.
        // The server sometimes wraps reasoning text in markdown blockquotes.
        let lines = text.components(separatedBy: "\n")
        let cleaned = lines.map { line -> String in
            var l = line
            // Strip one level of blockquote: "> text" → "text", ">text" → "text"
            if l.hasPrefix("> ") {
                l = String(l.dropFirst(2))
            } else if l.hasPrefix(">") && !l.hasPrefix(">>") {
                l = String(l.dropFirst(1))
            }
            return l
        }
        text = cleaned.joined(separator: "\n")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// Renders a tool call with status indicator, collapsible INPUT/OUTPUT sections,
/// and result display — matching the Open WebUI web frontend's ToolCallDisplay.
private struct ToolCallView: View {
    let toolCall: ToolCall
    var isStreaming: Bool = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header button — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    statusIcon
                    headerLabel
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable details section
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 12) {
                    // INPUT section
                    inputSection

                    // OUTPUT section (only when we have a result)
                    if let result = toolCall.result, !result.isEmpty {
                        outputSection(result)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .background(AppColors.fileAttachmentBg.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.borderColor.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch toolCall.status {
        case .pending, .executing:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.emerald600)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.red500)
        }
    }

    // MARK: - Header Label

    @ViewBuilder
    private var headerLabel: some View {
        switch toolCall.status {
        case .pending:
            Text(toolCall.function.name)
                .font(AppFont.caption(size: 12).weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
        case .executing:
            (Text("Executing ").foregroundStyle(AppColors.textTertiary)
             + Text(toolCall.function.name).foregroundStyle(AppColors.textSecondary).bold()
             + Text("...").foregroundStyle(AppColors.textTertiary))
                .font(AppFont.caption(size: 12))
        case .completed:
            if toolCall.result != nil {
                (Text("View Result from ").foregroundStyle(AppColors.textTertiary)
                 + Text(toolCall.function.name).foregroundStyle(AppColors.textSecondary).bold())
                    .font(AppFont.caption(size: 12))
            } else {
                (Text("Executed ").foregroundStyle(AppColors.textTertiary)
                 + Text(toolCall.function.name).foregroundStyle(AppColors.textSecondary).bold())
                    .font(AppFont.caption(size: 12))
            }
        case .error:
            (Text("Failed: ").foregroundStyle(AppColors.red500)
             + Text(toolCall.function.name).foregroundStyle(AppColors.textSecondary).bold())
                .font(AppFont.caption(size: 12))
        }
    }

    // MARK: - INPUT Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("INPUT")
                .font(.system(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(AppColors.textTertiary)

            let parsed = parseArgumentsToKeyValues(toolCall.function.arguments)
            if let keyValues = parsed {
                // Render as compact key-value pairs
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(keyValues.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        HStack(alignment: .top, spacing: 8) {
                            Text(key)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(minWidth: 50, alignment: .leading)
                            Text(value)
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textPrimary)
                                .textSelection(.enabled)
                                .lineLimit(5)
                        }
                    }
                }
            } else {
                // Render as raw JSON code block
                Text(formatJSON(toolCall.function.arguments))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.codeBlockBg.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - OUTPUT Section

    private func outputSection(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("OUTPUT")
                .font(.system(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(AppColors.textTertiary)

            // Try parsing as JSON for formatted display
            if let data = result.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                Text(formatJSON(result))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.codeBlockBg.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(result)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(20)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.codeBlockBg.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Helpers

    /// Parse JSON arguments into key-value pairs for compact display.
    /// Returns nil if the arguments aren't a flat JSON object.
    private func parseArgumentsToKeyValues(_ args: String) -> [String: String]? {
        guard let data = args.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var result: [String: String] = [:]
        for (key, value) in obj {
            if let str = value as? String {
                result[key] = str
            } else if let num = value as? NSNumber {
                result[key] = num.stringValue
            } else if let bool = value as? Bool {
                result[key] = bool ? "true" : "false"
            } else {
                // Complex value — fall back to JSON display for the whole thing
                return nil
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Pretty-print a JSON string.
    private func formatJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return json }
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

// MARK: - Sources / Citations View

private struct SourcesView: View {
    let sources: [ChatSourceReference]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 11))
                    Text("\(sources.count) source\(sources.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundStyle(AppColors.accentBlue)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sources, id: \.id) { source in
                        sourceRow(source)
                    }
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func sourceRow(_ source: ChatSourceReference) -> some View {
        if let urlString = source.url, let url = URL(string: urlString) {
            Link(destination: url) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.accentBlue)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.title ?? url.host ?? urlString)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.accentBlue)
                            .lineLimit(1)
                        if let snippet = source.snippet {
                            Text(snippet)
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(6)
                .background(AppColors.fileAttachmentBg.opacity(0.6))
                .cornerRadius(6)
            }
        } else {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title ?? "Source")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    if let snippet = source.snippet {
                        Text(snippet)
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(6)
            .background(AppColors.fileAttachmentBg.opacity(0.6))
            .cornerRadius(6)
        }
    }
}

// MARK: - Message Error Banner

private struct MessageErrorBanner: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.red500)
            Text(content)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.red500)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.red500.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.red500.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Code Execution View

private struct CodeExecutionView: View {
    let execution: ChatCodeExecution
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)
                    Text(execution.name ?? "Code Execution")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    if let lang = execution.language {
                        Text("(\(lang))")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Code block
                    if let code = execution.code, !code.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CODE")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(code)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .textSelection(.enabled)
                            }
                            .padding(6)
                            .background(AppColors.codeBlockBg)
                            .cornerRadius(4)
                        }
                    }

                    // Output
                    if let result = execution.result {
                        if let output = result.output, !output.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("OUTPUT")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(AppColors.textTertiary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(output)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(AppColors.emerald600)
                                        .textSelection(.enabled)
                                }
                                .padding(6)
                                .background(AppColors.codeBlockBg)
                                .cornerRadius(4)
                            }
                        }

                        if let error = result.error, !error.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ERROR")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(AppColors.red500)
                                Text(error)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(AppColors.red500)
                                    .textSelection(.enabled)
                                    .padding(6)
                                    .background(AppColors.red500.opacity(0.08))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .background(AppColors.fileAttachmentBg.opacity(0.8))
        .cornerRadius(8)
    }

    private var statusIcon: String {
        if execution.result?.error != nil { return "xmark.circle.fill" }
        if execution.result != nil { return "checkmark.circle.fill" }
        return "gearshape.fill"
    }

    private var statusColor: Color {
        if execution.result?.error != nil { return AppColors.red500 }
        if execution.result != nil { return AppColors.emerald600 }
        return AppColors.textTertiary
    }
}

// MARK: - Follow-Up Chips View

private struct FollowUpChipsView: View {
    let suggestions: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    onTap(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.accentBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.accentBlue.opacity(0.1))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(AppColors.accentBlue.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }
}
