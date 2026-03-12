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
    @State private var renameTarget: String?
    @State private var renameText: String = ""
    @State private var folders: [ChatFolder] = []
    @State private var searchFieldRef = SidebarSearchFieldRef()

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Search Field (supports tag: prefix autocomplete)
            SidebarSearchField(appState: appState, ref: searchFieldRef)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // MARK: - Pinned Models
            if !appState.pinnedModels.isEmpty {
                PinnedModelsSection(appState: appState)

                Divider()
                    .padding(.horizontal, 10)
            }

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
                    Text(appState.searchText.isEmpty ? String(localized: "sidebar.noConversations") : String(localized: "sidebar.noResults"))
                        .foregroundStyle(AppColors.textTertiary)
                        .font(AppFont.body(size: 13))
                } else {
                    ForEach(groupedConversations, id: \.label) { group in
                        Section {
                            ForEach(group.conversations) { conversation in
                                ConversationRow(conversation: conversation, isStreaming: appState.isChatStreaming(conversation.id))
                                .tag(conversation.id)
                                .contextMenu {
                                    Button {
                                        Task { await appState.shareConversation(conversation.id) }
                                    } label: {
                                        Label(String(localized: "conversation.share"), systemImage: "square.and.arrow.up")
                                    }

                                    Button {
                                        Task { await appState.downloadConversation(conversation.id) }
                                    } label: {
                                        Label(String(localized: "conversation.download"), systemImage: "arrow.down.circle")
                                    }

                                    Button {
                                        renameText = conversation.title
                                        renameTarget = conversation.id
                                    } label: {
                                        Label(String(localized: "conversation.rename"), systemImage: "pencil")
                                    }

                                    Divider()

                                    Button {
                                        Task { await appState.togglePinConversation(conversation.id) }
                                    } label: {
                                        Label(conversation.isPinned ? String(localized: "conversation.unpin") : String(localized: "conversation.pin"), systemImage: conversation.isPinned ? "bookmark.slash" : "bookmark")
                                    }

                                    Button {
                                        Task { await appState.cloneConversation(conversation.id) }
                                    } label: {
                                        Label(String(localized: "conversation.clone"), systemImage: "doc.on.doc")
                                    }

                                    if !folders.isEmpty {
                                        Menu {
                                            ForEach(folders) { folder in
                                                Button(folder.name) {
                                                    Task { await appState.moveConversation(conversation.id, toFolder: folder.id) }
                                                }
                                            }
                                            if conversation.folder_id != nil {
                                                Divider()
                                                Button(String(localized: "conversation.removeFromFolder")) {
                                                    Task { await appState.moveConversation(conversation.id, toFolder: nil) }
                                                }
                                            }
                                        } label: {
                                            Label(String(localized: "conversation.move"), systemImage: "folder")
                                        }
                                    }

                                    Button {
                                        appState.showTagEditor(for: conversation.id)
                                    } label: {
                                        Label(String(localized: "conversation.manageTags"), systemImage: "tag")
                                    }

                                    Button {
                                        Task { await appState.archiveConversation(conversation.id) }
                                    } label: {
                                        Label(String(localized: "conversation.archive"), systemImage: "archivebox")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        deleteTarget = conversation.id
                                    } label: {
                                        Label(String(localized: "conversation.delete"), systemImage: "trash")
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

                    // Load more pagination trigger
                    if appState.hasMoreConversations && !appState.isDemoMode {
                        Section {
                            HStack {
                                Spacer()
                                if appState.isLoadingMoreConversations {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button(String(localized: "sidebar.loadMore")) {
                                        Task { await appState.loadMoreConversations() }
                                    }
                                    .buttonStyle(.plain)
                                    .font(AppFont.body(size: 12))
                                    .foregroundStyle(AppColors.textTertiary)
                                }
                                Spacer()
                            }
                            .onAppear {
                                // Auto-load when scrolled into view
                                Task { await appState.loadMoreConversations() }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(AppColors.sidebarBg)
        .overlay(alignment: .top) {
            // Tag autocomplete dropdown — rendered at the sidebar level
            // so it floats above the NSOutlineView-backed List.
            if searchFieldRef.showAutocomplete && !searchFieldRef.suggestions.isEmpty {
                TagAutocompleteDropdown(
                    suggestions: searchFieldRef.suggestions,
                    onSelect: { tag in
                        searchFieldRef.onSelectTag?(tag)
                    }
                )
                .padding(.horizontal, 10)
                // Position below: search field top padding (8) + field height (~30) + bottom padding (4)
                .padding(.top, 42)
            }
        }
        .task {
            folders = await appState.loadFolders()
        }
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
                    .help(String(localized: "sidebar.settingsHelp"))
                }
                .padding(.horizontal, 14)
                .frame(height: 60)
            }
            .background(AppColors.sidebarBg)
        }
        .confirmationDialog(
            String(localized: "deleteChat.title"),
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "conversation.delete"), role: .destructive) {
                if let id = deleteTarget {
                    deleteTarget = nil
                    Task { await appState.deleteConversation(id) }
                }
            }
            Button(String(localized: "cancel"), role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text("deleteChat.message")
        }
        .alert(String(localized: "renameChat.title"), isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField(String(localized: "renameChat.fieldLabel"), text: $renameText)
            Button(String(localized: "rename")) {
                if let id = renameTarget {
                    let newTitle = renameText
                    renameTarget = nil
                    Task { await appState.renameConversation(id, newTitle: newTitle) }
                }
            }
            Button(String(localized: "cancel"), role: .cancel) {
                renameTarget = nil
            }
        } message: {
            Text("renameChat.message")
        }
        .sheet(isPresented: $appState.isTagEditorPresented) {
            if let convId = appState.tagEditorConversationID {
                TagEditorSheet(appState: appState, conversationId: convId)
            }
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
            return [ConversationGroup(label: String(localized: "sidebar.group.conversations"), conversations: appState.filteredConversations)]
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
        if !today.isEmpty { groups.append(ConversationGroup(label: String(localized: "sidebar.group.today"), conversations: today)) }
        if !yesterday.isEmpty { groups.append(ConversationGroup(label: String(localized: "sidebar.group.yesterday"), conversations: yesterday)) }
        if !prev7.isEmpty { groups.append(ConversationGroup(label: String(localized: "sidebar.group.prev7Days"), conversations: prev7)) }
        if !prev30.isEmpty { groups.append(ConversationGroup(label: String(localized: "sidebar.group.prev30Days"), conversations: prev30)) }

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

// MARK: - Pinned Models Section

/// Compact pinned models list shown above the conversation list.
/// Clicking a pinned model creates a new chat with that model selected.
struct PinnedModelsSection: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Section header
            Text("sidebar.pinnedModels")
                .font(AppFont.semibold(size: 10))
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 14)
                .padding(.top, 4)

            ForEach(appState.pinnedModels) { model in
                Button {
                    appState.newConversationWithModel(model)
                } label: {
                    HStack(spacing: 8) {
                        ModelAvatarView(
                            model: model,
                            serverURL: appState.serverURL,
                            apiKey: appState.activeServer?.apiKey ?? "",
                            size: 20
                        )

                        Text(model.displayName)
                            .font(AppFont.body(size: 12))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        // Parameter size badge
                        if let paramSize = model.parameterSize {
                            Text(paramSize)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textTertiary)
                        }

                        // Loaded indicator
                        if model.isLoaded {
                            Circle()
                                .fill(.green)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        appState.togglePinModel(model)
                    } label: {
                        Label(String(localized: "pinnedModel.unpinFromSidebar"), systemImage: "pin.slash")
                    }

                    Button {
                        appState.selectedModel = model
                    } label: {
                        Label(String(localized: "pinnedModel.selectModel"), systemImage: "checkmark.circle")
                    }

                    if !appState.isDefaultModel(model) {
                        Button {
                            appState.setDefaultModel(model)
                        } label: {
                            Label(String(localized: "pinnedModel.setAsDefault"), systemImage: "star")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Conversation Row

/// A single conversation row showing the title and optional streaming indicator.
private struct ConversationRow: View {
    let conversation: ChatListItem
    var isStreaming: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(conversation.title)
                .font(AppFont.body(size: 13))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if isStreaming {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }
        }
    }
}
