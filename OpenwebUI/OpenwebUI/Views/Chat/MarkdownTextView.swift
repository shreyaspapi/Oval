import SwiftUI

/// Renders markdown-style content as styled text.
/// Uses Open WebUI's exact color palette and font sizes.
struct MarkdownTextView: View {
    let content: String

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

    private func parseInlineFormatting(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[...]

        while !remaining.isEmpty {
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
