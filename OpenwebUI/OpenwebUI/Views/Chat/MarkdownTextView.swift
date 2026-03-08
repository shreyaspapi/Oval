import SwiftUI

/// Renders markdown-style content as styled text.
/// Uses Open WebUI's exact color palette and font sizes.
/// When `sources` are provided, citation references like [1], [2] in the content
/// become tappable links that open the corresponding source URL.
struct MarkdownTextView: View {
    let content: String
    var sources: [ChatSourceReference]?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .codeBlock(let language, let code):
                    CodeBlockView(language: language, code: code)
                case .text(let text):
                    Text(parseInlineMarkdown(text))
                        .font(AppFont.body())
                        .foregroundStyle(AppColors.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Block Parsing

    private enum Block {
        case text(String)
        case codeBlock(language: String, code: String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0
        var currentText = ""

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                if !currentText.isEmpty {
                    result.append(.text(currentText.trimmingCharacters(in: .newlines)))
                    currentText = ""
                }

                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1

                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }

                result.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                i += 1
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

    // MARK: - Inline Markdown

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        var result = AttributedString()

        let lines = text.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                result.append(AttributedString("\n"))
            }

            // Headings
            if line.hasPrefix("### ") {
                var heading = AttributedString(String(line.dropFirst(4)))
                heading.font = AppFont.h3
                heading.foregroundColor = AppColors.textHeading
                result.append(heading)
                continue
            } else if line.hasPrefix("## ") {
                var heading = AttributedString(String(line.dropFirst(3)))
                heading.font = AppFont.h2
                heading.foregroundColor = AppColors.textHeading
                result.append(heading)
                continue
            } else if line.hasPrefix("# ") {
                var heading = AttributedString(String(line.dropFirst(2)))
                heading.font = AppFont.h1
                heading.foregroundColor = AppColors.textHeading
                result.append(heading)
                continue
            }

            // List items
            var processedLine = line
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                var bullet = AttributedString("  \u{2022} ")
                bullet.foregroundColor = AppColors.textListMarker
                result.append(bullet)
                processedLine = String(line.dropFirst(2))
            } else if let match = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                var num = AttributedString("  " + String(line[match]))
                num.foregroundColor = AppColors.textListMarker
                result.append(num)
                processedLine = String(line[match.upperBound...])
            }

            result.append(parseInlineFormatting(processedLine))
        }

        return result
    }

    // MARK: - Citation Pattern

    /// Regex matching citation references: [1], [2,3], [1][2], [1, 2, 3]
    /// Excludes footnote-style [^1] references.
    private static let citationRegex = try! NSRegularExpression(
        pattern: #"\[(\d[\d,\s]*)\]"#,
        options: []
    )

    /// Resolve the URL for a source at a given 1-based index.
    /// Checks url, then metadata fields (matching Conduit's SourceHelper).
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
        // Try to extract domain from URL
        if let urlStr = source.url ?? source.metadata?["url"] ?? source.metadata?["source"],
           let url = URL(string: urlStr), let host = url.host {
            // Strip common prefixes for cleaner display
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return domain
        }
        // Fall back to title
        if let title = source.title, !title.isEmpty {
            return title.count > 30 ? String(title.prefix(27)) + "..." : title
        }
        return nil
    }

    // MARK: - Inline Formatting

    private func parseInlineFormatting(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[...]

        while !remaining.isEmpty {
            // Markdown link: [text](url)
            if remaining.hasPrefix("["),
               let closeBracket = remaining.dropFirst(1).firstIndex(of: "]") {
                let afterBracket = remaining[remaining.index(after: closeBracket)...]
                if afterBracket.hasPrefix("("),
                   let closeParen = afterBracket.dropFirst(1).firstIndex(of: ")") {
                    let linkText = String(remaining[remaining.index(after: remaining.startIndex)..<closeBracket])
                    let urlString = String(afterBracket[afterBracket.index(after: afterBracket.startIndex)..<closeParen])

                    // Check if this is actually a citation like [1](url) — treat as citation badge
                    if let _ = linkText.range(of: #"^\d[\d,\s]*$"#, options: .regularExpression) {
                        // Citation with explicit URL — render as badge
                        let indices = parseCitationIndices(linkText)
                        result.append(buildCitationBadge(indices: indices, overrideURL: URL(string: urlString)))
                    } else if let url = URL(string: urlString) {
                        // Regular markdown link
                        var attr = AttributedString(linkText)
                        attr.link = url
                        attr.foregroundColor = AppColors.accentBlue
                        attr.underlineStyle = .single
                        result.append(attr)
                    } else {
                        // Invalid URL — render as plain text
                        var attr = AttributedString("[\(linkText)](\(urlString))")
                        attr.foregroundColor = AppColors.textPrimary
                        result.append(attr)
                    }
                    remaining = remaining[remaining.index(after: closeParen)...]
                    continue
                }

                // Check for citation: [1], [2,3], etc. (not footnote [^1])
                let bracketContent = String(remaining[remaining.index(after: remaining.startIndex)..<closeBracket])
                if !bracketContent.hasPrefix("^"),
                   let _ = bracketContent.range(of: #"^\d[\d,\s]*$"#, options: .regularExpression),
                   sources != nil, !(sources?.isEmpty ?? true) {
                    let indices = parseCitationIndices(bracketContent)
                    if !indices.isEmpty && indices.allSatisfy({ sourceURL(at: $0) != nil }) {
                        result.append(buildCitationBadge(indices: indices, overrideURL: nil))
                        remaining = remaining[remaining.index(after: closeBracket)...]
                        continue
                    }
                }

                // Not a link or citation — fall through to render as regular text
            }

            // Bold: **text**
            if remaining.hasPrefix("**"),
               let endRange = remaining.dropFirst(2).range(of: "**") {
                let boldText = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound])
                var attr = AttributedString(boldText)
                attr.font = AppFont.semibold()
                attr.foregroundColor = AppColors.textBold
                result.append(attr)
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Inline code: `text`
            if remaining.hasPrefix("`") && !remaining.hasPrefix("``"),
               let endIdx = remaining.dropFirst(1).firstIndex(of: "`") {
                let codeText = String(remaining[remaining.index(after: remaining.startIndex)..<endIdx])
                var attr = AttributedString(codeText)
                attr.font = AppFont.mono(size: 13)
                attr.foregroundColor = AppColors.inlineCodeText
                attr.backgroundColor = AppColors.inlineCodeBg
                result.append(attr)
                remaining = remaining[remaining.index(after: endIdx)...]
                continue
            }

            // Italic: *text*
            if remaining.hasPrefix("*"),
               let endIdx = remaining.dropFirst(1).firstIndex(of: "*") {
                let italicText = String(remaining[remaining.index(after: remaining.startIndex)..<endIdx])
                var attr = AttributedString(italicText)
                attr.font = .system(size: 14).italic()
                attr.foregroundColor = AppColors.textItalic
                result.append(attr)
                remaining = remaining[remaining.index(after: endIdx)...]
                continue
            }

            // Regular character
            var char = AttributedString(String(remaining.first!))
            char.foregroundColor = AppColors.textPrimary
            result.append(char)
            remaining = remaining.dropFirst(1)
        }

        return result
    }

    // MARK: - Citation Helpers

    /// Parse comma-separated citation indices from bracket content like "1", "1,2,3", "1, 2".
    private func parseCitationIndices(_ content: String) -> [Int] {
        content.components(separatedBy: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 }
    }

    /// Build an attributed string for a citation badge: superscript numbered link.
    /// For single citations like [1], shows the number as a linked superscript.
    /// For multi-citations like [1,2], shows each number.
    private func buildCitationBadge(indices: [Int], overrideURL: URL?) -> AttributedString {
        var result = AttributedString()

        for (i, index) in indices.enumerated() {
            let url = overrideURL ?? sourceURL(at: index)
            let label = sourceLabel(at: index)

            // Superscript-style numbered badge
            var badge = AttributedString("\(index)")
            badge.font = .system(size: 10, weight: .semibold)
            badge.foregroundColor = .white
            badge.backgroundColor = AppColors.accentBlue
            badge.baselineOffset = 4

            if let url {
                badge.link = url
                // When there's a source label (domain), show it as a tooltip-style suffix
                if let label {
                    var labelAttr = AttributedString(" \(label)")
                    labelAttr.font = .system(size: 10, weight: .medium)
                    labelAttr.foregroundColor = AppColors.accentBlue
                    labelAttr.baselineOffset = 4
                    labelAttr.link = url
                    badge.append(labelAttr)
                }
            }

            if i > 0 {
                var sep = AttributedString(" ")
                sep.font = .system(size: 10)
                sep.baselineOffset = 4
                result.append(sep)
            }
            result.append(badge)
        }

        // Add a thin space after the badge group so it doesn't stick to the next word
        var space = AttributedString("\u{2009}")
        space.font = .system(size: 10)
        result.append(space)

        return result
    }
}

// MARK: - Code Block View with Liquid Glass header

private struct CodeBlockView: View {
    let language: String
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Liquid Glass effect
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

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(AppFont.mono(size: 13))
                    .foregroundStyle(AppColors.codeBlockText)
                    .textSelection(.enabled)
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
