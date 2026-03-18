import SwiftUI
import Textual

/// Renders markdown-style content as styled text using Textual.
/// Uses Open WebUI's exact color palette and font sizes.
/// When `sources` are provided, citation references like [1], [2] in the content
/// become tappable links that open the corresponding source URL.
struct MarkdownTextView: View, Equatable {
    let content: String
    var sources: [ChatSourceReference]?

    nonisolated static func == (lhs: MarkdownTextView, rhs: MarkdownTextView) -> Bool {
        lhs.content == rhs.content && lhs.sources == rhs.sources
    }

    var body: some View {
        let blocks = Self.parseBlocks(preprocessedContent)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .codeBlock(let language, let code):
                    CodeBlockView(language: language, code: code)
                case .text(let text):
                    StructuredText(markdown: text)
                        .textual.textSelection(.enabled)
                        .textual.structuredTextStyle(OvalMarkdownStyle())
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }

    // MARK: - Block Parsing

    private enum Block {
        case text(String)
        case codeBlock(language: String, code: String)
    }

    /// Split markdown content into text blocks and fenced code blocks.
    /// Code blocks are rendered separately so they sit outside Textual's
    /// text-selection overlay, which would otherwise swallow button taps
    /// and scroll gestures.
    ///
    /// Follows CommonMark rules for fenced code blocks:
    /// - Opening fence: 3+ backticks optionally followed by a language hint
    /// - Closing fence: at least as many backticks as the opening, with
    ///   nothing else on the line (except optional whitespace)
    nonisolated private static func parseBlocks(_ content: String) -> [Block] {
        var result: [Block] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0
        var currentText = ""

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Count leading backticks to detect an opening fence (3+)
            let backtickCount = trimmed.prefix(while: { $0 == "`" }).count
            let afterBackticks = String(trimmed.dropFirst(backtickCount))
                .trimmingCharacters(in: .whitespaces)

            // Opening fence: 3+ backticks, the info string must not contain backticks
            if backtickCount >= 3 && !afterBackticks.contains("`") {
                if !currentText.isEmpty {
                    result.append(.text(currentText.trimmingCharacters(in: .newlines)))
                    currentText = ""
                }

                let language = afterBackticks
                var codeLines: [String] = []
                i += 1

                // Closing fence: a line whose trimmed content is ONLY backticks
                // (at least as many as the opening fence)
                while i < lines.count {
                    let closeTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    let closeBackticks = closeTrimmed.prefix(while: { $0 == "`" }).count
                    let isClosingFence = closeBackticks >= backtickCount
                        && closeTrimmed.allSatisfy({ $0 == "`" || $0.isWhitespace })
                    if isClosingFence { break }
                    codeLines.append(lines[i])
                    i += 1
                }

                result.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                i += 1 // skip closing fence
            } else {
                currentText += (currentText.isEmpty ? "" : "\n") + line
                i += 1
            }
        }

        if !currentText.isEmpty {
            result.append(.text(currentText.trimmingCharacters(in: .newlines)))
        }

        return result
    }

    // MARK: - Citation Preprocessing

    /// Pre-process markdown to convert citation references [1], [2] into markdown links
    /// when sources are available, so Textual renders them as tappable links.
    private var preprocessedContent: String {
        guard let sources, !sources.isEmpty else { return content }

        var result = content
        // Match citation patterns: [1], [2], etc. (not [^1] footnotes, not [text](url) links)
        // Process in reverse order of index to avoid offset issues
        let nsContent = result as NSString
        let pattern = #"\[(\d+)\](?!\()"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }

        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsContent.length))

        // Process matches in reverse to preserve string positions
        for match in matches.reversed() {
            let fullRange = match.range
            let indexRange = match.range(at: 1)
            let indexStr = nsContent.substring(with: indexRange)

            guard let index = Int(indexStr),
                  index >= 1,
                  index <= sources.count else { continue }

            if let url = sourceURL(at: index) {
                let label = sourceLabel(at: index) ?? "\(index)"
                let replacement = "[\(label)](\(url.absoluteString))"
                result = (result as NSString).replacingCharacters(in: fullRange, with: replacement)
            }
        }

        return result
    }

    // MARK: - Source Helpers

    /// Resolve the URL for a source at a given 1-based index.
    private func sourceURL(at oneBasedIndex: Int) -> URL? {
        guard let sources, oneBasedIndex >= 1, oneBasedIndex <= sources.count else { return nil }
        let source = sources[oneBasedIndex - 1]
        if let urlStr = source.url, let url = URL(string: urlStr) { return url }
        if let meta = source.metadata {
            for key in ["url", "source", "link"] {
                if let urlStr = meta[key], let url = URL(string: urlStr) { return url }
            }
        }
        return nil
    }

    /// Resolve a short display label for a source (domain or truncated title).
    private func sourceLabel(at oneBasedIndex: Int) -> String? {
        guard let sources, oneBasedIndex >= 1, oneBasedIndex <= sources.count else { return nil }
        let source = sources[oneBasedIndex - 1]
        if let urlStr = source.url ?? source.metadata?["url"] ?? source.metadata?["source"],
           let url = URL(string: urlStr), let host = url.host {
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return domain
        }
        if let title = source.title, !title.isEmpty {
            return title.count > 30 ? String(title.prefix(27)) + "..." : title
        }
        return nil
    }
}

// MARK: - Oval Markdown Style

/// Custom StructuredText style matching Open WebUI's dark theme.
struct OvalMarkdownStyle: StructuredText.Style {
    var inlineStyle: InlineStyle {
        InlineStyle()
            .code(
                .monospaced,
                .fontScale(0.93),
                .foregroundColor(AppColors.inlineCodeText),
                .backgroundColor(AppColors.inlineCodeBg)
            )
            .emphasis(.italic, .foregroundColor(AppColors.textItalic))
            .strong(.fontWeight(.semibold), .foregroundColor(AppColors.textBold))
            .link(.foregroundColor(AppColors.accentBlue), .underlineStyle(.single))
    }

    var headingStyle: OvalHeadingStyle {
        OvalHeadingStyle()
    }

    var paragraphStyle: StructuredText.DefaultParagraphStyle {
        .default
    }

    var blockQuoteStyle: StructuredText.DefaultBlockQuoteStyle {
        .default
    }

    var codeBlockStyle: StructuredText.DefaultCodeBlockStyle {
        .default
    }

    var tableStyle: StructuredText.DefaultTableStyle {
        .default
    }

    var tableCellStyle: StructuredText.DefaultTableCellStyle {
        .default
    }

    var thematicBreakStyle: StructuredText.DividerThematicBreakStyle {
        .divider
    }

    var listItemStyle: StructuredText.DefaultListItemStyle {
        .default
    }

    var unorderedListMarker: StructuredText.HierarchicalSymbolListMarker {
        .hierarchical(.disc, .circle, .square)
    }

    var orderedListMarker: StructuredText.DecimalListMarker {
        .decimal
    }
}

// MARK: - Heading Style

struct OvalHeadingStyle: StructuredText.HeadingStyle {
    private static let fontScales: [CGFloat] = [1.72, 1.43, 1.15, 1, 0.875, 0.85]

    func makeBody(configuration: Configuration) -> some View {
        let level = min(configuration.headingLevel, 6)
        let scale = Self.fontScales[level - 1]

        configuration.label
            .textual.fontScale(scale)
            .fontWeight(level <= 2 ? .bold : .semibold)
            .foregroundStyle(AppColors.textHeading)
            .textual.blockSpacing(.fontScaled(top: 1.2, bottom: 0.4))
    }
}

// MARK: - Code Block View with Liquid Glass header

/// Standalone code block rendered outside Textual's view hierarchy so
/// the copy button and horizontal scroll work without interference
/// from the text-selection overlay.
private struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language label and copy button
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(AppFont.caption())
                    .foregroundStyle(AppColors.textTertiary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? "Copied!" : "Copy code")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppColors.codeBlockHeader)

            // Code content with horizontal scrolling
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(AppFont.mono(size: 13))
                    .foregroundStyle(AppColors.codeBlockText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(14)
            }
            .background(AppColors.codeBlockBg)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.codeBlockBorder, lineWidth: 0.5)
        )
        .glassEffect(
            .regular.tint(AppColors.codeBlockGlass.opacity(0.2)),
            in: .rect(cornerRadius: 8)
        )
    }
}
