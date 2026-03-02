import SwiftUI

/// A single message matching Open WebUI's bubble style.
/// User messages: right-aligned in bg-gray-850 bubble with Liquid Glass.
/// Assistant messages: left-aligned with avatar, no bubble.
struct MessageBubbleView: View {
    let message: ChatMessage
    var isStreaming: Bool = false

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

            // Text content
            if !message.content.isEmpty {
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
        }
        .contextMenu {
            Button("Copy") {
                copyToClipboard(message.content)
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

                // Message content
                if message.content.isEmpty && isStreaming {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(AppColors.textTertiary)
                                .frame(width: 6, height: 6)
                                .opacity(0.6)
                        }
                    }
                    .padding(.top, 4)
                } else {
                    MarkdownTextView(content: message.content)
                }

                // Action buttons (copy)
                if !isStreaming && !message.content.isEmpty {
                    HStack(spacing: 4) {
                        CopyButton(text: message.content)
                    }
                    .padding(.top, 4)
                }
            }
            .contextMenu {
                Button("Copy Message") {
                    copyToClipboard(message.content)
                }
            }
        }
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
        // Format: "data:image/png;base64,iVBOR..."
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
