import SwiftUI

/// Discord-style server rail on the far left edge.
/// Shows server icons as rounded squares with a selection pill indicator.
/// Always visible regardless of server count. ~56px wide.
struct ServerRailView: View {
    @Bindable var appState: AppState

    @State private var hoveredServerID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Server List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(appState.servers) { server in
                        serverIcon(for: server)
                    }
                }
                .padding(.vertical, 10)
            }

            Spacer(minLength: 0)

            // MARK: - Add Server Button
            VStack(spacing: 0) {
                Divider()
                Button {
                    appState.showAddServer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.green400)
                        .frame(width: 40, height: 40)
                        .background(AppColors.green400.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .help("Add Server")
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .frame(width: 56)
        .background(AppColors.sidebarBg)
    }

    // MARK: - Server Icon

    @ViewBuilder
    private func serverIcon(for server: ServerConfig) -> some View {
        let isActive = server.id == appState.activeServerID
        let isHovered = hoveredServerID == server.id

        HStack(spacing: 0) {
            // Selection pill indicator (Discord-style left edge pill)
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.textPrimary)
                .frame(width: 3, height: isActive ? 32 : (isHovered ? 18 : 0))
                .animation(.easeInOut(duration: 0.15), value: isActive)
                .animation(.easeInOut(duration: 0.15), value: isHovered)

            Spacer(minLength: 0)

            // Server icon button
            Button {
                Task { await appState.selectServer(server.id) }
            } label: {
                ZStack {
                    // Background shape — transitions from rounded-rect to circle on active
                    RoundedRectangle(cornerRadius: isActive ? 14 : 20)
                        .fill(isActive ? AppColors.accentBlue : AppColors.serverIconBg)
                        .frame(width: 40, height: 40)
                        .animation(.easeInOut(duration: 0.2), value: isActive)

                    // Server initial or emoji
                    if server.iconEmoji == "🌐" || server.iconEmoji.isEmpty {
                        Text(serverInitial(for: server))
                            .font(AppFont.bold(size: 15))
                            .foregroundStyle(isActive ? .white : AppColors.textSecondary)
                    } else {
                        Text(server.iconEmoji)
                            .font(.system(size: 18))
                    }
                }
            }
            .buttonStyle(.plain)
            .help(server.name.isEmpty ? server.url : server.name)
            .contextMenu {
                Button("Copy Server URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(server.url, forType: .string)
                }
                Divider()
                Button("Remove Server", role: .destructive) {
                    Task { await appState.removeServer(server.id) }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 56)
        .onHover { hovering in
            hoveredServerID = hovering ? server.id : nil
        }
    }

    // MARK: - Helpers

    private func serverInitial(for server: ServerConfig) -> String {
        let name = server.name.isEmpty ? server.url : server.name
        // Get first letter, uppercased
        let cleaned = name
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        return String(cleaned.prefix(1)).uppercased()
    }
}
