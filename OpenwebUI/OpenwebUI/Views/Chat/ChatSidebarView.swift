import SwiftUI

/// Conversations sidebar with time-grouped chat list matching Open WebUI web.
///
/// Layout:
/// - Search field
/// - Conversations grouped by: Today / Yesterday / Previous 7 Days / Previous 30 Days / Month+Year
/// - Bottom: user info + settings
struct ChatSidebarView: View {
    @Bindable var appState: AppState

    @State private var deleteTarget: String?

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Search Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
                TextField("Search conversations", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .font(AppFont.body(size: 13))
                if !appState.searchText.isEmpty {
                    Button {
                        appState.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppColors.searchFieldBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // MARK: - Conversations List
            List(selection: $appState.selectedConversationID) {
                if appState.isLoadingConversations {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                } else if appState.filteredConversations.isEmpty {
                    Text(appState.searchText.isEmpty ? "No conversations" : "No results")
                        .foregroundStyle(AppColors.textTertiary)
                        .font(AppFont.body(size: 13))
                } else {
                    ForEach(groupedConversations, id: \.label) { group in
                        Section {
                            ForEach(group.conversations) { conversation in
                                ConversationRow(conversation: conversation)
                                .tag(conversation.id)
                                .contextMenu {
                                    Button("Rename...") {
                                        // Placeholder for rename
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        deleteTarget = conversation.id
                                    }
                                }
                            }
                        } header: {
                            Text(group.label)
                                .font(AppFont.semibold(size: 11))
                                .foregroundStyle(AppColors.textTertiary)
                                .textCase(.uppercase)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(AppColors.sidebarBg)
        .onChange(of: appState.selectedConversationID) { _, newId in
            guard !appState.suppressConversationSelection else { return }
            if let id = newId {
                Task { await appState.selectConversation(id) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            // MARK: - Bottom Bar: User + Settings
            VStack(spacing: 0) {
                Divider()
                    .overlay(AppColors.borderColor)
                HStack(spacing: 10) {
                    // User name
                    if let user = appState.currentUser {
                        Text(user.name ?? "User")
                            .font(AppFont.body(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Settings button — opens the Settings window (Cmd+,)
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings (Cmd+,)")
                }
                .padding(.horizontal, 14)
                .frame(height: 60)
            }
            .background(AppColors.sidebarBg)
        }
        .confirmationDialog(
            "Delete Chat",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = deleteTarget {
                    deleteTarget = nil
                    Task { await appState.deleteConversation(id) }
                }
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text("Are you sure you want to delete this conversation? This action cannot be undone.")
        }
    }

    // MARK: - Time Grouping

    private struct ConversationGroup: Identifiable {
        let label: String
        let conversations: [ChatListItem]
        var id: String { label }
    }

    private var groupedConversations: [ConversationGroup] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
              let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday),
              let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday)
        else {
            return [ConversationGroup(label: "Conversations", conversations: appState.filteredConversations)]
        }

        var today: [ChatListItem] = []
        var yesterday: [ChatListItem] = []
        var prev7: [ChatListItem] = []
        var prev30: [ChatListItem] = []
        var older: [String: [ChatListItem]] = [:] // "Month Year" → items

        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMMM yyyy"

        for convo in appState.filteredConversations {
            guard let date = convo.updatedDate else {
                today.append(convo) // no date, show in today
                continue
            }

            if date >= startOfToday {
                today.append(convo)
            } else if date >= startOfYesterday {
                yesterday.append(convo)
            } else if date >= sevenDaysAgo {
                prev7.append(convo)
            } else if date >= thirtyDaysAgo {
                prev30.append(convo)
            } else {
                let key = monthYearFormatter.string(from: date)
                older[key, default: []].append(convo)
            }
        }

        var groups: [ConversationGroup] = []
        if !today.isEmpty { groups.append(ConversationGroup(label: "Today", conversations: today)) }
        if !yesterday.isEmpty { groups.append(ConversationGroup(label: "Yesterday", conversations: yesterday)) }
        if !prev7.isEmpty { groups.append(ConversationGroup(label: "Previous 7 Days", conversations: prev7)) }
        if !prev30.isEmpty { groups.append(ConversationGroup(label: "Previous 30 Days", conversations: prev30)) }

        // Sort older groups by date (most recent month first)
        let sortedOlderKeys = older.keys.sorted { a, b in
            let dateA = monthYearFormatter.date(from: a) ?? .distantPast
            let dateB = monthYearFormatter.date(from: b) ?? .distantPast
            return dateA > dateB
        }
        for key in sortedOlderKeys {
            if let items = older[key] {
                groups.append(ConversationGroup(label: key, conversations: items))
            }
        }

        return groups
    }
}

// MARK: - Conversation Row

/// A single conversation row showing the title only.
private struct ConversationRow: View {
    let conversation: ChatListItem

    var body: some View {
        Text(conversation.title)
            .font(AppFont.body(size: 13))
            .foregroundStyle(AppColors.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
