import Foundation
import Observation
import AppKit

// MARK: - Screen Enum

enum AppScreen: Equatable {
    case loading
    case connect
    case controls
    case chat
}

/// Top-level application state.
/// Manages servers, conversations, chat, and screen routing.
@MainActor
@Observable
final class AppState {

    // MARK: - Screen Routing

    var currentScreen: AppScreen = .loading

    // MARK: - Connection Flow

    var urlInput: String = "http://localhost:8080"
    var apiKeyInput: String = ""
    var emailInput: String = ""
    var passwordInput: String = ""
    var selectedAuthMethod: AuthMethod = .emailPassword
    var connectionError: String?
    var isConnecting: Bool = false

    // MARK: - Server Status

    var serverReachable: Bool = false
    var serverURL: String = ""
    var serverVersion: String?
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Servers

    var servers: [ServerConfig] = []
    var activeServerID: UUID?
    var showAddServer: Bool = false

    var activeServer: ServerConfig? {
        servers.first { $0.id == activeServerID }
    }

    // MARK: - Per-Server State

    var models: [AIModel] = []
    var conversations: [ChatListItem] = []
    var selectedConversationID: String?
    var currentUser: SessionUser?

    // MARK: - Chat

    var chatMessages: [ChatMessage] = []
    var selectedModel: AIModel?
    var messageInput: String = ""
    var isStreaming: Bool = false
    var streamingContent: String = ""
    var isLoadingConversations: Bool = false
    var isLoadingChat: Bool = false

    /// When true, the sidebar onChange handler should NOT call selectConversation().
    /// Used when programmatically setting selectedConversationID (e.g. after creating a new chat).
    var suppressConversationSelection: Bool = false

    // MARK: - Message Cache

    /// Cached messages keyed by conversation ID. Avoids re-fetching on every click.
    private var messageCache: [String: [ChatMessage]] = [:]

    // MARK: - Mini Chat (Spotlight-style overlay)

    var miniChatMessages: [ChatMessage] = []
    var miniMessageInput: String = ""
    var miniStreamingContent: String = ""
    var isMiniStreaming: Bool = false

    // MARK: - Features

    var isWebSearchEnabled: Bool = false

    // MARK: - Attachments

    var pendingAttachments: [PendingAttachment] = []

    func addAttachment(_ attachment: PendingAttachment) {
        pendingAttachments.append(attachment)
    }

    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    // MARK: - Sidebar

    var isSidebarVisible: Bool = true
    var searchText: String = ""

    var filteredConversations: [ChatListItem] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Toasts

    let toastManager = ToastManager()

    // MARK: - Speech

    let speechManager = SpeechManager()

    // MARK: - Window Preferences

    var alwaysOnTop: Bool = false {
        didSet { applyAlwaysOnTop() }
    }
    var launchAtLogin: Bool = false {
        didSet { LaunchAtLoginManager.setEnabled(launchAtLogin) }
    }

    // MARK: - Dependencies

    private let configManager: ConfigManager
    let trayManager: TrayManager
    let hotkeyManager: HotkeyManager
    let miniChatWindowManager: MiniChatWindowManager
    private let connectionManager = ServerConnectionManager()
    private var client: OpenWebUIClient?

    init() {
        self.configManager = ConfigManager()
        self.trayManager = TrayManager()
        self.hotkeyManager = HotkeyManager()
        self.miniChatWindowManager = MiniChatWindowManager()
        self.launchAtLogin = LaunchAtLoginManager.isEnabled()
        loadServers()
    }

    // MARK: - Lifecycle

    func onAppear() async {
        trayManager.setup(appState: self)
        miniChatWindowManager.setup(appState: self)
        setupHotkeys()

        if let server = activeServer {
            // Already have a saved server, try to reconnect
            serverURL = server.url
            client = OpenWebUIClient(baseURL: server.url, apiKey: server.apiKey)
            let healthy = await connectionManager.checkHealth(url: server.url)
            if healthy {
                serverReachable = true
                serverVersion = await connectionManager.fetchVersion(url: server.url)
                await loadModels()
                await loadConversations()
                await loadUser()
                currentScreen = .chat
            } else {
                currentScreen = .connect
            }
        } else {
            // No saved server, go to connect
            try? await Task.sleep(for: .seconds(1))
            currentScreen = .connect
        }

        trayManager.updateMenu()
    }

    func onDisappear() {
        trayManager.teardown()
        hotkeyManager.stop()
        miniChatWindowManager.teardown()
    }

    // MARK: - Hotkey Setup

    private func setupHotkeys() {
        hotkeyManager.onToggleMiniWindow = { [weak self] in
            self?.miniChatWindowManager.toggle()
        }
        hotkeyManager.onToggleMainWindow = { [weak self] in
            self?.toggleMainWindow()
        }
        hotkeyManager.onPasteToMiniChat = { [weak self] in
            self?.miniChatWindowManager.showWithClipboard()
        }
        hotkeyManager.start()
    }

    private func toggleMainWindow() {
        if let window = NSApp.windows.first(where: {
            $0.title.contains("Oval") && !($0 is NSPanel)
        }) {
            if window.isVisible && window.isKeyWindow {
                window.orderOut(nil)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - Always On Top

    func applyAlwaysOnTop() {
        for window in NSApp.windows where !(window is NSPanel) {
            window.level = alwaysOnTop ? .floating : .normal
        }
    }

    // MARK: - Connection

    /// Connect using the currently selected auth method.
    func connect() async {
        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            connectionError = "Please enter a server URL"
            return
        }

        isConnecting = true
        connectionError = nil

        // Check health first
        let healthy = await connectionManager.checkHealth(url: url)
        guard healthy else {
            connectionError = "Cannot reach server at \(url). Make sure it's running."
            isConnecting = false
            return
        }

        // Authenticate based on selected method
        let token: String
        let authMethod: AuthMethod
        var userEmail: String?

        switch selectedAuthMethod {
        case .emailPassword:
            let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let password = passwordInput

            guard !email.isEmpty else {
                connectionError = "Please enter your email"
                isConnecting = false
                return
            }
            guard !password.isEmpty else {
                connectionError = "Please enter your password"
                isConnecting = false
                return
            }

            do {
                let signInResponse = try await OpenWebUIClient.signIn(
                    baseURL: url, email: email, password: password
                )
                token = signInResponse.token
                authMethod = .emailPassword
                userEmail = email
            } catch {
                connectionError = error.localizedDescription
                isConnecting = false
                return
            }

        case .apiKey:
            let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                connectionError = "Please enter your API key"
                isConnecting = false
                return
            }
            token = key
            authMethod = .apiKey
        }

        // Fetch version
        serverVersion = await connectionManager.fetchVersion(url: url)
        serverURL = url
        serverReachable = true

        // Create server config with the obtained token
        let server = ServerConfig(
            name: "Server",
            url: url,
            apiKey: token,
            authMethod: authMethod,
            email: userEmail
        )

        servers = [server]
        activeServerID = server.id
        saveServers()

        // Initialize client with the token
        client = OpenWebUIClient(baseURL: url, apiKey: token)

        // Load data
        await loadModels()
        await loadConversations()
        await loadUser()

        // Clear sensitive input
        passwordInput = ""

        isConnecting = false
        currentScreen = .chat

        trayManager.updateMenu()
    }

    func disconnect() {
        client = nil
        serverReachable = false
        serverURL = ""
        serverVersion = nil
        clearServerState()
        servers = []
        activeServerID = nil
        saveServers()
        currentScreen = .connect
        trayManager.updateMenu()
    }

    // MARK: - Navigation

    func openInBrowser() {
        guard !serverURL.isEmpty, let url = URL(string: serverURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(serverURL, forType: .string)
        toastManager.show("URL copied to clipboard", style: .success)
    }

    func goToChat() {
        currentScreen = .chat
    }

    func goToSettings() {
        // Open the native macOS Settings window (Cmd+,)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: - Server Management

    func addServer(_ server: ServerConfig) async {
        servers.append(server)
        saveServers()
        await selectServer(server.id)
    }

    func removeServer(_ id: UUID) async {
        servers.removeAll { $0.id == id }
        if activeServerID == id {
            activeServerID = servers.first?.id
            if let server = activeServer {
                await connectToServer(server)
            } else {
                clearServerState()
            }
        }
        saveServers()
    }

    func selectServer(_ id: UUID) async {
        guard id != activeServerID else { return }
        activeServerID = id
        saveServers()
        if let server = activeServer {
            await connectToServer(server)
        }
    }

    private func connectToServer(_ server: ServerConfig) async {
        client = OpenWebUIClient(baseURL: server.url, apiKey: server.apiKey)
        serverURL = server.url
        clearServerState()

        let healthy = await connectionManager.checkHealth(url: server.url)
        serverReachable = healthy

        if healthy {
            serverVersion = await connectionManager.fetchVersion(url: server.url)
            async let modelsResult: () = loadModels()
            async let chatsResult: () = loadConversations()
            async let userResult: () = loadUser()
            _ = await (modelsResult, chatsResult, userResult)
        }

        trayManager.updateMenu()
    }

    private func clearServerState() {
        models = []
        conversations = []
        chatMessages = []
        selectedConversationID = nil
        selectedModel = nil
        currentUser = nil
        streamingContent = ""
        isStreaming = false
        searchText = ""
        messageCache = [:]
    }

    // MARK: - Models

    func loadModels() async {
        guard let client else { return }
        do {
            models = try await client.listModels()
            if selectedModel == nil, let first = models.first {
                selectedModel = first
            }
        } catch {
            toastManager.show("Failed to load models", style: .error)
        }
    }

    // MARK: - Conversations

    func loadConversations(silent: Bool = false) async {
        guard let client else { return }
        if !silent { isLoadingConversations = true }
        do {
            var chats = try await client.listChats(page: 1)
            // Sort descending by updated_at (newest first)
            chats.sort { ($0.updated_at ?? 0) > ($1.updated_at ?? 0) }
            conversations = chats
            // Prefetch messages for all conversations in background
            prefetchConversations()
        } catch {
            if !silent {
                toastManager.show("Failed to load conversations", style: .error)
            }
        }
        if !silent { isLoadingConversations = false }
    }

    func selectConversation(_ id: String) async {
        selectedConversationID = id

        // Use cached messages immediately if available
        if let cached = messageCache[id] {
            chatMessages = cached
            // Refresh in background (silent update, no loading indicator)
            Task {
                await refreshChatMessages(id, silent: true)
            }
        } else {
            await loadChatMessages(id)
        }
    }

    func newConversation() {
        selectedConversationID = nil
        chatMessages = []
        messageInput = ""
        pendingAttachments = []
    }

    func createAndSelectConversation() async {
        guard let client else { return }
        do {
            let chat = try await client.createChat(title: "New Chat")
            await loadConversations()
            selectedConversationID = chat.id
            chatMessages = []
        } catch {
            toastManager.show("Failed to create conversation", style: .error)
        }
    }

    func deleteConversation(_ id: String) async {
        guard let client else { return }
        do {
            try await client.deleteChat(id: id)
            messageCache.removeValue(forKey: id)
            if selectedConversationID == id {
                selectedConversationID = nil
                chatMessages = []
            }
            await loadConversations()
        } catch {
            toastManager.show("Failed to delete conversation", style: .error)
        }
    }

    private func loadChatMessages(_ chatId: String) async {
        guard let client else { return }
        isLoadingChat = true
        do {
            let chat = try await client.getChat(id: chatId)
            let messages = chat.chat?.history?.linearMessages() ?? []
            messageCache[chatId] = messages
            // Only update UI if this conversation is still selected
            if selectedConversationID == chatId {
                chatMessages = messages
            }
        } catch {
            toastManager.show("Failed to load messages", style: .error)
            if selectedConversationID == chatId {
                chatMessages = []
            }
        }
        isLoadingChat = false
    }

    /// Silently refresh messages for a conversation (no loading spinner).
    private func refreshChatMessages(_ chatId: String, silent: Bool) async {
        guard let client else { return }
        if !silent { isLoadingChat = true }
        do {
            let chat = try await client.getChat(id: chatId)
            let messages = chat.chat?.history?.linearMessages() ?? []
            messageCache[chatId] = messages
            if selectedConversationID == chatId {
                chatMessages = messages
            }
        } catch {
            // Silent refresh — don't show errors
        }
        if !silent { isLoadingChat = false }
    }

    /// Prefetch messages for all visible conversations in the background.
    func prefetchConversations() {
        guard client != nil else { return }
        for conversation in conversations {
            if messageCache[conversation.id] == nil {
                Task {
                    await refreshChatMessages(conversation.id, silent: true)
                }
            }
        }
    }

    // MARK: - User

    func loadUser() async {
        guard let client else { return }
        do {
            currentUser = try await client.getSessionUser()
        } catch {}
    }

    // MARK: - Send Message

    func sendMessage() async {
        let text = messageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty, !isStreaming else { return }
        guard let model = selectedModel, let client else {
            toastManager.show("Select a model first", style: .error)
            return
        }

        let isNewConversation = selectedConversationID == nil

        // Separate image and file attachments
        let imageAttachments = attachments.filter { $0.isImage }
        let fileAttachments = attachments.filter { !$0.isImage }

        // Upload non-image files to the server
        var uploadedFileRefs: [CompletionFileRef] = []
        var chatFileRefs: [ChatFileRef] = []
        for file in fileAttachments {
            do {
                let uploaded = try await client.uploadFile(
                    fileName: file.fileName,
                    mimeType: file.mimeType,
                    data: file.data
                )
                uploadedFileRefs.append(CompletionFileRef(type: "file", id: uploaded.id))
                chatFileRefs.append(ChatFileRef(
                    name: file.fileName,
                    type: file.mimeType,
                    size: file.data.count,
                    fileId: uploaded.id
                ))
            } catch {
                toastManager.show("Failed to upload \(file.fileName)", style: .error)
            }
        }

        // Build image data URIs
        let imageDataURIs = imageAttachments.compactMap { $0.dataURI }

        // Add user message locally
        let userMsg = ChatMessage(
            id: UUID().uuidString,
            role: "user",
            content: text,
            model: nil,
            timestamp: Date().timeIntervalSince1970,
            parentId: chatMessages.last?.id,
            childrenIds: nil,
            images: imageDataURIs.isEmpty ? nil : imageDataURIs,
            files: chatFileRefs.isEmpty ? nil : chatFileRefs
        )
        chatMessages.append(userMsg)
        messageInput = ""
        pendingAttachments = []

        let assistantId = UUID().uuidString

        // ── Step 1: Create chat on server if this is a new conversation ──
        if isNewConversation {
            let title = String(text.prefix(100))
            let blob = buildChatBlob(title: title, assistantId: assistantId, assistantModel: model.id)

            do {
                let created = try await client.createChatWithHistory(blob: blob)
                // Suppress onChange so it doesn't re-fetch messages from server
                suppressConversationSelection = true
                selectedConversationID = created.id
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    suppressConversationSelection = false
                }
            } catch {
                toastManager.show("Failed to create chat: \(error.localizedDescription)", style: .error)
            }
        }

        // Build completion messages (multimodal for the current message if it has images)
        var completionMsgs: [CompletionMessage] = []
        for msg in chatMessages {
            if let images = msg.images, !images.isEmpty {
                var parts: [ContentPart] = []
                if !msg.content.isEmpty {
                    parts.append(.text(msg.content))
                }
                for imageURI in images {
                    parts.append(.imageURL(imageURI))
                }
                completionMsgs.append(CompletionMessage(role: msg.role, content: .parts(parts)))
            } else {
                completionMsgs.append(CompletionMessage(role: msg.role, content: .text(msg.content)))
            }
        }

        // ── Step 2: Start streaming ──
        isStreaming = true
        streamingContent = ""

        let assistantMsg = ChatMessage(
            id: assistantId,
            role: "assistant",
            content: "",
            model: model.id,
            timestamp: Date().timeIntervalSince1970,
            parentId: userMsg.id,
            childrenIds: nil
        )
        chatMessages.append(assistantMsg)

        do {
            let stream = await client.streamChat(
                model: model.id,
                messages: completionMsgs,
                files: uploadedFileRefs.isEmpty ? nil : uploadedFileRefs,
                webSearch: isWebSearchEnabled
            )
            for try await delta in stream {
                streamingContent += delta
                if let idx = chatMessages.lastIndex(where: { $0.id == assistantId }) {
                    chatMessages[idx] = ChatMessage(
                        id: assistantId,
                        role: "assistant",
                        content: streamingContent,
                        model: model.id,
                        timestamp: Date().timeIntervalSince1970,
                        parentId: userMsg.id,
                        childrenIds: nil
                    )
                }
            }
        } catch {
            toastManager.show("Stream error: \(error.localizedDescription)", style: .error)
        }

        isStreaming = false
        streamingContent = ""

        // ── Step 3: Save final state to server ──
        if let convId = selectedConversationID {
            messageCache[convId] = chatMessages

            // Use first user message as temporary title
            let fallbackTitle = chatMessages.first(where: { $0.role == "user" })
                .map { String($0.content.prefix(100)) } ?? "New Chat"
            let blob = buildChatBlob(title: fallbackTitle, assistantId: nil, assistantModel: nil)
            Task {
                do {
                    _ = try await client.updateChat(id: convId, blob: blob)
                } catch {
                    // Non-critical: chat still works locally
                }
            }

            // ── Step 4: Generate a proper title for new conversations ──
            if isNewConversation {
                Task {
                    await generateAndSetTitle(chatId: convId, modelId: model.id)
                }
            }
        }

        // Refresh sidebar to show new/updated conversation
        Task { await loadConversations(silent: true) }
    }

    // MARK: - Title Generation

    /// Generate a title for the conversation using the LLM via the tasks API,
    /// then update the chat on the server and refresh the sidebar.
    private func generateAndSetTitle(chatId: String, modelId: String) async {
        guard let client else { return }

        // Send the last 2 messages (user + assistant) for title generation
        let recentMessages = chatMessages.suffix(2).map {
            TitleGenerationMessage(role: $0.role, content: $0.content)
        }

        do {
            if let title = try await client.generateTitle(
                model: modelId,
                messages: recentMessages,
                chatId: chatId
            ) {
                // Update the chat on the server with the generated title
                let blob = buildChatBlob(title: title, assistantId: nil, assistantModel: nil)
                _ = try await client.updateChat(id: chatId, blob: blob)

                // Refresh sidebar to show the new title
                await loadConversations(silent: true)
            }
        } catch {
            // Non-critical — the fallback title from the user message is already saved
        }
    }

    // MARK: - Chat Blob Builder

    /// Builds a ChatBlob from the current chatMessages for server persistence.
    private func buildChatBlob(title: String, assistantId: String?, assistantModel: String?) -> ChatBlob {
        // Build the history tree: messages dict + currentId
        var historyDict: [String: ChatBlobMessage] = [:]
        var flatMessages: [ChatBlobMessage] = []

        for (index, msg) in chatMessages.enumerated() {
            let nextId = (index + 1 < chatMessages.count) ? chatMessages[index + 1].id : nil
            let childrenIds: [String] = nextId != nil ? [nextId!] : []

            let blobMsg = ChatBlobMessage(
                id: msg.id,
                role: msg.role,
                content: msg.content,
                model: msg.model,
                parentId: msg.parentId,
                childrenIds: childrenIds,
                timestamp: msg.timestamp,
                images: msg.images,
                files: msg.files
            )
            historyDict[msg.id] = blobMsg
            flatMessages.append(blobMsg)
        }

        // If we're about to create the assistant placeholder, add it
        if let aId = assistantId {
            let placeholder = ChatBlobMessage(
                id: aId,
                role: "assistant",
                content: "",
                model: assistantModel,
                parentId: chatMessages.last?.id,
                childrenIds: [],
                timestamp: Date().timeIntervalSince1970,
                images: nil,
                files: nil
            )
            historyDict[aId] = placeholder
            flatMessages.append(placeholder)

            // Update the last message's children to include the assistant
            if let lastMsg = chatMessages.last, var entry = historyDict[lastMsg.id] {
                let updated = ChatBlobMessage(
                    id: entry.id,
                    role: entry.role,
                    content: entry.content,
                    model: entry.model,
                    parentId: entry.parentId,
                    childrenIds: entry.childrenIds + [aId],
                    timestamp: entry.timestamp,
                    images: entry.images,
                    files: entry.files
                )
                historyDict[lastMsg.id] = updated
            }
        }

        let currentId = flatMessages.last?.id
        let history = ChatBlobHistory(messages: historyDict, currentId: currentId)

        return ChatBlob(title: title, history: history, messages: flatMessages)
    }

    func stopStreaming() {
        // Currently streaming will finish on its own; this is a placeholder
        // for future cancellation support
        isStreaming = false
    }

    // MARK: - Mini Chat

    /// Send a message in the mini chat window. This is a lightweight version
    /// that doesn't persist to the server — it's for quick one-off queries.
    func sendMiniMessage() async {
        let text = miniMessageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isMiniStreaming else { return }
        guard let model = selectedModel, let client else {
            toastManager.show("Connect to a server first", style: .error)
            return
        }

        // Add user message
        let userMsg = ChatMessage(
            id: UUID().uuidString,
            role: "user",
            content: text,
            model: nil,
            timestamp: Date().timeIntervalSince1970,
            parentId: miniChatMessages.last?.id,
            childrenIds: nil
        )
        miniChatMessages.append(userMsg)
        miniMessageInput = ""

        let assistantId = UUID().uuidString
        isMiniStreaming = true
        miniStreamingContent = ""

        // Add assistant placeholder
        let assistantMsg = ChatMessage(
            id: assistantId,
            role: "assistant",
            content: "",
            model: model.id,
            timestamp: Date().timeIntervalSince1970,
            parentId: userMsg.id,
            childrenIds: nil
        )
        miniChatMessages.append(assistantMsg)

        // Build completion messages
        let completionMsgs = miniChatMessages.map { msg in
            CompletionMessage(role: msg.role, content: .text(msg.content))
        }

        do {
            let stream = await client.streamChat(
                model: model.id,
                messages: completionMsgs,
                files: nil,
                webSearch: false
            )
            for try await delta in stream {
                miniStreamingContent += delta
                if let idx = miniChatMessages.lastIndex(where: { $0.id == assistantId }) {
                    miniChatMessages[idx] = ChatMessage(
                        id: assistantId,
                        role: "assistant",
                        content: miniStreamingContent,
                        model: model.id,
                        timestamp: Date().timeIntervalSince1970,
                        parentId: userMsg.id,
                        childrenIds: nil
                    )
                }
            }
        } catch {
            toastManager.show("Stream error: \(error.localizedDescription)", style: .error)
        }

        isMiniStreaming = false
        miniStreamingContent = ""
    }

    func stopMiniStreaming() {
        isMiniStreaming = false
    }

    func newMiniChat() {
        miniChatMessages = []
        miniMessageInput = ""
        miniStreamingContent = ""
    }

    /// Copy the last assistant message to clipboard.
    func copyLastAssistantMessage() {
        if let lastAssistant = miniChatMessages.last(where: { $0.role == "assistant" }) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lastAssistant.content, forType: .string)
            toastManager.show("Copied to clipboard", style: .success)
        } else if let lastAssistant = chatMessages.last(where: { $0.role == "assistant" }) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lastAssistant.content, forType: .string)
            toastManager.show("Copied to clipboard", style: .success)
        }
    }

    // MARK: - Persistence

    private func loadServers() {
        let config = configManager.load()
        servers = config.servers
        activeServerID = config.activeServerID
    }

    private func saveServers() {
        let config = ConfigManager.Config(
            servers: servers,
            activeServerID: activeServerID
        )
        configManager.save(config)
    }
}
