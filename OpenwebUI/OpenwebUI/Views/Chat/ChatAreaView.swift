import SwiftUI
import UniformTypeIdentifiers

/// Main chat area — messages in the middle, input at bottom.
/// Handles drag & drop over the entire area with a visual overlay.
struct ChatAreaView: View {
    @Bindable var appState: AppState

    @State private var isDragOver = false

    var body: some View {
        VStack(spacing: 0) {
            if appState.chatMessages.isEmpty && appState.selectedConversationID == nil {
                WelcomeView(appState: appState)
            } else {
                MessageListView(appState: appState)
            }

            ChatInputView(appState: appState)
        }
        .background(AppColors.chatBg)
        .overlay {
            // Full-screen drag & drop overlay
            if isDragOver {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppColors.accentBlue.opacity(0.08))
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(AppColors.accentBlue, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))

                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(AppColors.accentBlue)
                        Text("Drop files here")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Images, documents, and other files")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(20)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDragOver)
        .onDrop(of: [.fileURL, .image, .png, .jpeg, .pdf], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
            return true
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        addFileFromURL(url)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        let attachment = PendingAttachment(
                            fileName: "image.png",
                            mimeType: "image/png",
                            data: data,
                            isImage: true
                        )
                        appState.addAttachment(attachment)
                    }
                }
            }
        }
    }

    // MARK: - Paste

    // MARK: - Helpers

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

// MARK: - Welcome View (Empty State)

private struct WelcomeView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // Logo with Liquid Glass
                ZStack {
                    Circle()
                        .fill(AppColors.avatarBg)
                        .frame(width: 64, height: 64)
                    Text("O")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.avatarText)
                }
                .glassEffect(.regular, in: .circle)

                Text("How can I help you today?")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppColors.welcomeText)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
