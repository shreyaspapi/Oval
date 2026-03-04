import Foundation
import Observation
import AppKit
import os.log

private let ovalLog = Logger(subsystem: "com.oval.app", category: "chat")

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
    var currentPage: Int = 1
    var hasMoreConversations: Bool = true
    var isLoadingMoreConversations: Bool = false

    /// Active streaming tasks — cancelled when user taps stop.
    private var streamingTask: Task<Void, Never>?
    private var miniStreamingTask: Task<Void, Never>?

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

    // MARK: - Demo Mode

    /// When true, the app is in demo mode with mock data (no real server).
    /// Used for App Store review so reviewers can see the full UI.
    var isDemoMode: Bool = false

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
    let ttsManager = TTSManager()

    // MARK: - Voice Mode (on-device STT/TTS via RunAnywhere)

    let voiceModeManager = VoiceModeManager()
    let voiceModeWindowManager = VoiceModeWindowManager()
    var isVoiceModeActive = false

    /// Open or close the voice mode floating window.
    func setVoiceModeActive(_ active: Bool) {
        isVoiceModeActive = active
        if active {
            voiceModeWindowManager.show()
        } else {
            voiceModeWindowManager.hide()
        }
    }

    // MARK: - Realtime Transcription (live captions)

    let realtimeTranscriptionManager = RealtimeTranscriptionManager()
    let transcriptionWindowManager = TranscriptionWindowManager()
    let speakerDiarizationManager = SpeakerDiarizationManager()
    var isRealtimeTranscriptionActive = false

    /// Open or close the realtime transcription floating window.
    func setRealtimeTranscriptionActive(_ active: Bool) {
        isRealtimeTranscriptionActive = active
        if active {
            transcriptionWindowManager.show()
        } else {
            transcriptionWindowManager.hide()
        }
    }

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

    /// Internal access for VoiceModeManager to call the server LLM.
    var currentClient: OpenWebUIClient? { client }

    // MARK: - Socket.IO

    let socketService = SocketService()
    /// Continuation for the Socket.IO streaming path — finished when the server sends completion done.
    private var socketStreamContinuation: AsyncThrowingStream<OpenWebUIClient.StreamDelta, Error>.Continuation?
    /// The message ID currently being streamed via Socket.IO
    private var socketStreamingMessageId: String?

    init() {
        self.configManager = ConfigManager()
        self.trayManager = TrayManager()
        self.hotkeyManager = HotkeyManager()
        self.miniChatWindowManager = MiniChatWindowManager()
        self.launchAtLogin = LaunchAtLoginManager.isEnabled()
        loadServers()
        setupSocketEventHandler()
    }

    // MARK: - Lifecycle

    func onAppear() async {
        trayManager.setup(appState: self)
        miniChatWindowManager.setup(appState: self)
        voiceModeManager.setup(appState: self)
        voiceModeWindowManager.setup(appState: self)
        transcriptionWindowManager.setup(appState: self)
        realtimeTranscriptionManager.setDiarizationManager(speakerDiarizationManager)
        setupHotkeys()

        // Initialize RunAnywhere SDK for on-device STT/TTS
        Task {
            await RunAnywhereService.shared.initialize()
        }

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
        voiceModeWindowManager.teardown()
        transcriptionWindowManager.teardown()
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

        case .sso:
            // SSO authentication is handled via connectWithSSO() method
            connectionError = "Please use the SSO login button"
            isConnecting = false
            return
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

    /// Connect after SSO/OAuth flow captured a JWT token.
    func connectWithSSO(token: String) async {
        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            connectionError = "Please enter a server URL"
            return
        }

        isConnecting = true
        connectionError = nil

        serverVersion = await connectionManager.fetchVersion(url: url)
        serverURL = url
        serverReachable = true

        let server = ServerConfig(
            name: "Server",
            url: url,
            apiKey: token,
            authMethod: .sso,
            email: nil
        )

        servers = [server]
        activeServerID = server.id
        saveServers()

        client = OpenWebUIClient(baseURL: url, apiKey: token)

        await loadModels()
        await loadConversations()
        await loadUser()

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
            // Connect Socket.IO for real-time events
            socketService.connect(url: server.url, token: server.apiKey)

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
        socketService.disconnect()
    }

    /// Clear the message cache so conversations reload fresh from the server.
    func clearMessageCache() {
        messageCache = [:]
        // Reload current conversation if one is selected
        if let convId = selectedConversationID {
            Task { await loadChatMessages(convId) }
        }
    }

    // MARK: - Socket.IO Event Handler

    /// Wire up the Socket.IO event handler to update messages with status events
    /// and streaming content received via the real-time channel.
    private func setupSocketEventHandler() {
        socketService.onEvent = { [weak self] chatId, messageId, eventType, data in
            Task { @MainActor in
                self?.handleSocketEvent(chatId: chatId, messageId: messageId, type: eventType, data: data)
            }
        }
    }

    private func handleSocketEvent(chatId: String, messageId: String, type: String, data: [String: Any]) {
        switch type {
        case "status":
            // Web search progress, knowledge search, etc.
            guard let statusEvent = SocketService.parseStatusEvent(from: data) else { return }
            if let msgId = socketStreamingMessageId,
               let idx = chatMessages.lastIndex(where: { $0.id == msgId }) {
                var msg = chatMessages[idx]
                var history = msg.statusHistory ?? []
                // Replace last event with same action if it's updating (e.g. search in-progress → done)
                if let lastIdx = history.lastIndex(where: { $0.action == statusEvent.action && !$0.done }) {
                    history[lastIdx] = statusEvent
                } else {
                    history.append(statusEvent)
                }
                msg.statusHistory = history
                chatMessages[idx] = msg
            }

        case "chat:completion":
            // Streaming content via Socket.IO
            if let done = data["done"] as? Bool, done {
                // Stream finished
                socketStreamContinuation?.yield(.done)
                socketStreamContinuation?.finish()
                socketStreamContinuation = nil
                return
            }
            if let content = data["content"] as? String, !content.isEmpty {
                socketStreamContinuation?.yield(.content(content))
            }

        case "message":
            // Direct content append
            if let content = data["content"] as? String {
                socketStreamContinuation?.yield(.content(content))
            }

        case "replace":
            // Full content replacement — emit as a special content with marker
            if let content = data["content"] as? String {
                // Reset streaming content and replace
                streamingContent = content
                if let msgId = socketStreamingMessageId,
                   let idx = chatMessages.lastIndex(where: { $0.id == msgId }) {
                    let msg = chatMessages[idx]
                    var updated = ChatMessage(
                        id: msg.id,
                        role: msg.role,
                        content: content,
                        model: msg.model,
                        timestamp: msg.timestamp,
                        parentId: msg.parentId,
                        childrenIds: msg.childrenIds
                    )
                    // Preserve statusHistory and toolCalls
                    updated.statusHistory = msg.statusHistory
                    updated.toolCalls = msg.toolCalls
                    updated.toolCallId = msg.toolCallId
                    chatMessages[idx] = updated
                }
            }

        default:
            break
        }
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
        currentPage = 1
        hasMoreConversations = true
        do {
            var chats = try await client.listChats(page: 1)
            // Sort descending by updated_at (newest first)
            chats.sort { ($0.updated_at ?? 0) > ($1.updated_at ?? 0) }
            conversations = chats
            // If we got fewer than a full page, there are no more
            if chats.count < 50 { hasMoreConversations = false }
            // Prefetch messages for all conversations in background
            prefetchConversations()
        } catch {
            if !silent {
                toastManager.show("Failed to load conversations", style: .error)
            }
        }
        if !silent { isLoadingConversations = false }
    }

    /// Load the next page of conversations and append to the list.
    func loadMoreConversations() async {
        guard let client, hasMoreConversations, !isLoadingMoreConversations else { return }
        isLoadingMoreConversations = true
        let nextPage = currentPage + 1
        do {
            var chats = try await client.listChats(page: nextPage)
            if chats.isEmpty {
                hasMoreConversations = false
            } else {
                currentPage = nextPage
                chats.sort { ($0.updated_at ?? 0) > ($1.updated_at ?? 0) }
                // Filter out duplicates
                let existingIds = Set(conversations.map(\.id))
                let newChats = chats.filter { !existingIds.contains($0.id) }
                conversations.append(contentsOf: newChats)
                if chats.count < 50 { hasMoreConversations = false }
                // Prefetch new conversations
                for convo in newChats {
                    if messageCache[convo.id] == nil {
                        Task { await refreshChatMessages(convo.id, silent: true) }
                    }
                }
            }
        } catch {
            // Silent — don't show error for pagination
        }
        isLoadingMoreConversations = false
    }

    func selectConversation(_ id: String) async {
        selectedConversationID = id

        // In demo mode, just use the cache (no server to fetch from)
        if isDemoMode {
            chatMessages = messageCache[id] ?? []
            return
        }

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

    func renameConversation(_ id: String, newTitle: String) async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        if isDemoMode {
            if let idx = conversations.firstIndex(where: { $0.id == id }) {
                conversations[idx] = ChatListItem(
                    id: id,
                    title: title,
                    updated_at: conversations[idx].updated_at,
                    created_at: conversations[idx].created_at
                )
            }
            return
        }

        guard let client else { return }
        do {
            // Build a blob with the new title and current messages
            let currentMessages = messageCache[id] ?? []
            let oldMessages = chatMessages
            // Temporarily use cached messages to build the blob
            if selectedConversationID == id && !currentMessages.isEmpty {
                chatMessages = currentMessages
            }
            let blob = buildChatBlob(title: title, assistantId: nil, assistantModel: nil)
            if selectedConversationID == id {
                chatMessages = oldMessages
            }
            _ = try await client.updateChat(id: id, blob: blob)
            await loadConversations(silent: true)
        } catch {
            toastManager.show("Failed to rename: \(error.localizedDescription)", style: .error)
        }
    }

    func deleteConversation(_ id: String) async {
        if isDemoMode {
            messageCache.removeValue(forKey: id)
            conversations.removeAll { $0.id == id }
            if selectedConversationID == id {
                selectedConversationID = nil
                chatMessages = []
            }
            return
        }

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

            // DEBUG: Log statusHistory presence
            let msgsWithStatus = messages.filter { $0.statusHistory != nil && !($0.statusHistory?.isEmpty ?? true) }
            if !msgsWithStatus.isEmpty {
                ovalLog.info("[Oval] loadChatMessages: \(msgsWithStatus.count) messages have statusHistory in chat \(chatId)")
                for msg in msgsWithStatus {
                    ovalLog.info("[Oval]   msg[\(msg.id)] role=\(msg.role) statusHistory.count=\(msg.statusHistory?.count ?? 0)")
                    for s in msg.statusHistory ?? [] {
                        ovalLog.info("[Oval]     action=\(s.action) done=\(s.done) queries=\(s.queries ?? []) urls=\(s.urls ?? [])")
                    }
                }
            } else {
                ovalLog.debug("[Oval] loadChatMessages: no messages with statusHistory in chat \(chatId) (total: \(messages.count))")
            }

            messageCache[chatId] = messages
            // Only update UI if this conversation is still selected
            if selectedConversationID == chatId {
                chatMessages = messages
            }
        } catch {
            toastManager.show("Failed to load messages: \(error.localizedDescription)", style: .error)
            print("[Oval DEBUG] loadChatMessages error: \(error)")
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

            // DEBUG: Log statusHistory presence
            let msgsWithStatus = messages.filter { $0.statusHistory != nil && !($0.statusHistory?.isEmpty ?? true) }
            if !msgsWithStatus.isEmpty {
                ovalLog.info("[Oval] refreshChatMessages: \(msgsWithStatus.count) messages have statusHistory in chat \(chatId)")
                for msg in msgsWithStatus {
                    ovalLog.info("[Oval]   msg[\(msg.id)] role=\(msg.role) statusHistory.count=\(msg.statusHistory?.count ?? 0)")
                }
            } else {
                ovalLog.debug("[Oval] refreshChatMessages: no messages with statusHistory in chat \(chatId) (total: \(messages.count))")
            }

            messageCache[chatId] = messages
            if selectedConversationID == chatId {
                chatMessages = messages
            }
        } catch {
            // Silent refresh — don't show errors
            ovalLog.error("[Oval] refreshChatMessages error for \(chatId): \(error.localizedDescription)")
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
        // Route to demo handler if in demo mode
        if isDemoMode {
            await sendDemoMessage()
            return
        }

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
        let completionMsgs = Self.buildCompletionMessages(from: chatMessages)

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

        // Track the message ID for Socket.IO event routing
        socketStreamingMessageId = assistantId

        // Wrap streaming in a cancellable task
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Use Socket.IO path when connected (enables status events like web search progress)
                let useSocket = self.socketService.isConnected && self.selectedConversationID != nil
                let socketSid = useSocket ? self.socketService.sessionId : nil
                let socketChatId = useSocket ? self.selectedConversationID : nil

                let fileRefs = uploadedFileRefs.isEmpty ? nil : uploadedFileRefs
                let stream: AsyncThrowingStream<OpenWebUIClient.StreamDelta, Error>
                if useSocket, let sid = socketSid, let cid = socketChatId {
                    // Create a stream that will be fed by Socket.IO events
                    stream = AsyncThrowingStream { continuation in
                        self.socketStreamContinuation = continuation
                        // Fire the HTTP request to trigger the server (returns immediately)
                        Task {
                            _ = await client.streamChat(
                                model: model.id,
                                messages: completionMsgs,
                                files: fileRefs,
                                webSearch: self.isWebSearchEnabled,
                                sessionId: sid,
                                chatId: cid
                            )
                        }
                    }
                } else {
                    stream = await client.streamChat(
                        model: model.id,
                        messages: completionMsgs,
                        files: fileRefs,
                        webSearch: self.isWebSearchEnabled
                    )
                }
                // Accumulate tool call chunks keyed by index
                var toolCallAccumulator: [Int: (id: String, type: String, name: String, arguments: String)] = [:]

                for try await delta in stream {
                    if Task.isCancelled { break }
                    switch delta {
                    case .content(let text):
                        self.streamingContent += text
                    case .toolCall(let tc):
                        let idx = tc.index ?? 0
                        var entry = toolCallAccumulator[idx] ?? (id: "", type: "function", name: "", arguments: "")
                        if let id = tc.id { entry.id = id }
                        if let type = tc.type { entry.type = type }
                        if let name = tc.function?.name { entry.name += name }
                        if let args = tc.function?.arguments { entry.arguments += args }
                        toolCallAccumulator[idx] = entry
                    case .done:
                        break
                    }

                    // Build tool calls from streaming chunks (status = executing while streaming)
                    var completedToolCalls: [ToolCall] = toolCallAccumulator.sorted(by: { $0.key < $1.key }).compactMap { (_, entry) in
                        guard !entry.id.isEmpty, !entry.name.isEmpty else { return nil }
                        return ToolCall(id: entry.id, type: entry.type, function: ToolCall.ToolCallComplete(name: entry.name, arguments: entry.arguments), status: .executing)
                    }

                    // Also parse <details type="tool_calls"> from content — the server embeds
                    // tool results this way after executing tools server-side
                    let parsedFromContent = Self.parseToolCallDetails(from: self.streamingContent)
                    if !parsedFromContent.isEmpty {
                        // Merge: content-parsed tool calls (with results) take priority
                        let streamIds = Set(completedToolCalls.map(\.id))
                        for parsed in parsedFromContent {
                            if let idx = completedToolCalls.firstIndex(where: { $0.id == parsed.id }) {
                                completedToolCalls[idx] = parsed
                            } else if !streamIds.contains(parsed.id) {
                                completedToolCalls.append(parsed)
                            }
                        }
                    }

                    if let idx = self.chatMessages.lastIndex(where: { $0.id == assistantId }) {
                        var updated = ChatMessage(
                            id: assistantId,
                            role: "assistant",
                            content: self.streamingContent,
                            model: model.id,
                            timestamp: Date().timeIntervalSince1970,
                            parentId: userMsg.id,
                            childrenIds: nil
                        )
                        if !completedToolCalls.isEmpty {
                            updated.toolCalls = completedToolCalls
                        }
                        // Preserve statusHistory from Socket.IO events (set by handleSocketEvent)
                        updated.statusHistory = self.chatMessages[idx].statusHistory
                        self.chatMessages[idx] = updated
                    }
                }

                // After streaming ends, mark any remaining "executing" tool calls as completed
                if let idx = self.chatMessages.lastIndex(where: { $0.id == assistantId }) {
                    var finalMsg = self.chatMessages[idx]
                    if var toolCalls = finalMsg.toolCalls {
                        for i in toolCalls.indices {
                            if toolCalls[i].status == .executing || toolCalls[i].status == .pending {
                                toolCalls[i].status = .completed
                            }
                        }
                        finalMsg.toolCalls = toolCalls
                        self.chatMessages[idx] = finalMsg
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.toastManager.show("Stream error: \(error.localizedDescription)", style: .error)
                }
            }
        }
        streamingTask = task
        await task.value

        isStreaming = false
        streamingContent = ""
        streamingTask = nil
        socketStreamingMessageId = nil
        socketStreamContinuation = nil

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
                files: msg.files,
                toolCalls: msg.toolCalls,
                toolCallId: msg.toolCallId,
                statusHistory: msg.statusHistory?.map { StatusEventCodable(from: $0) }
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
                files: nil,
                toolCalls: nil,
                toolCallId: nil,
                statusHistory: nil
            )
            historyDict[aId] = placeholder
            flatMessages.append(placeholder)

            // Update the last message's children to include the assistant
            if let lastMsg = chatMessages.last, let entry = historyDict[lastMsg.id] {
                let updated = ChatBlobMessage(
                    id: entry.id,
                    role: entry.role,
                    content: entry.content,
                    model: entry.model,
                    parentId: entry.parentId,
                    childrenIds: entry.childrenIds + [aId],
                    timestamp: entry.timestamp,
                    images: entry.images,
                    files: entry.files,
                    toolCalls: entry.toolCalls,
                    toolCallId: entry.toolCallId,
                    statusHistory: entry.statusHistory
                )
                historyDict[lastMsg.id] = updated
            }
        }

        let currentId = flatMessages.last?.id
        let history = ChatBlobHistory(messages: historyDict, currentId: currentId)

        return ChatBlob(title: title, history: history, messages: flatMessages)
    }

    func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        streamingContent = ""
    }

    // MARK: - Edit Message

    /// Edit a user message's content and optionally re-send it.
    /// When resubmit is true, removes all messages after the edited one and re-streams.
    func editMessage(_ messageId: String, newContent: String, resubmit: Bool) async {
        guard let idx = chatMessages.firstIndex(where: { $0.id == messageId }) else { return }
        let original = chatMessages[idx]
        guard original.role == "user" else { return }

        // Update the message content in-place
        chatMessages[idx] = ChatMessage(
            id: original.id,
            role: original.role,
            content: newContent,
            model: original.model,
            timestamp: original.timestamp,
            parentId: original.parentId,
            childrenIds: original.childrenIds,
            images: original.images,
            files: original.files
        )

        if resubmit {
            // Remove all messages after this one (the old assistant responses)
            chatMessages = Array(chatMessages.prefix(idx + 1))

            // Re-stream from this point
            guard let model = selectedModel, let client else { return }

            let assistantId = UUID().uuidString
            isStreaming = true
            streamingContent = ""

            let assistantMsg = ChatMessage(
                id: assistantId,
                role: "assistant",
                content: "",
                model: model.id,
                timestamp: Date().timeIntervalSince1970,
                parentId: chatMessages[idx].id,
                childrenIds: nil
            )
            chatMessages.append(assistantMsg)

            // Build completion messages from the updated history (includes tool call context)
            let completionMsgs = Self.buildCompletionMessages(from: chatMessages)

            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let stream = await client.streamChat(
                        model: model.id,
                        messages: completionMsgs,
                        files: nil,
                        webSearch: self.isWebSearchEnabled
                    )
                    var toolCallAccumulator: [Int: (id: String, type: String, name: String, arguments: String)] = [:]

                    for try await delta in stream {
                        if Task.isCancelled { break }
                        switch delta {
                        case .content(let text):
                            self.streamingContent += text
                        case .toolCall(let tc):
                            let tcIdx = tc.index ?? 0
                            var entry = toolCallAccumulator[tcIdx] ?? (id: "", type: "function", name: "", arguments: "")
                            if let id = tc.id { entry.id = id }
                            if let type = tc.type { entry.type = type }
                            if let name = tc.function?.name { entry.name += name }
                            if let args = tc.function?.arguments { entry.arguments += args }
                            toolCallAccumulator[tcIdx] = entry
                        case .done:
                            break
                        }

                        var completedToolCalls: [ToolCall] = toolCallAccumulator.sorted(by: { $0.key < $1.key }).compactMap { (_, entry) in
                            guard !entry.id.isEmpty, !entry.name.isEmpty else { return nil }
                            return ToolCall(id: entry.id, type: entry.type, function: ToolCall.ToolCallComplete(name: entry.name, arguments: entry.arguments), status: .executing)
                        }
                        let parsedFromContent = Self.parseToolCallDetails(from: self.streamingContent)
                        for parsed in parsedFromContent {
                            if let i = completedToolCalls.firstIndex(where: { $0.id == parsed.id }) {
                                completedToolCalls[i] = parsed
                            } else if !completedToolCalls.contains(where: { $0.id == parsed.id }) {
                                completedToolCalls.append(parsed)
                            }
                        }

                        if let idx = self.chatMessages.lastIndex(where: { $0.id == assistantId }) {
                            var updated = ChatMessage(
                                id: assistantId,
                                role: "assistant",
                                content: self.streamingContent,
                                model: model.id,
                                timestamp: Date().timeIntervalSince1970,
                                parentId: self.chatMessages.count >= 2 ? self.chatMessages[self.chatMessages.count - 2].id : nil,
                                childrenIds: nil
                            )
                            if !completedToolCalls.isEmpty { updated.toolCalls = completedToolCalls }
                            // Preserve statusHistory from Socket.IO events
                            updated.statusHistory = self.chatMessages[idx].statusHistory
                            self.chatMessages[idx] = updated
                        }
                    }

                    // Finalize tool call statuses
                    if let idx = self.chatMessages.lastIndex(where: { $0.id == assistantId }) {
                        var finalMsg = self.chatMessages[idx]
                        if var toolCalls = finalMsg.toolCalls {
                            for i in toolCalls.indices where toolCalls[i].status == .executing || toolCalls[i].status == .pending {
                                toolCalls[i].status = .completed
                            }
                            finalMsg.toolCalls = toolCalls
                            self.chatMessages[idx] = finalMsg
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        self.toastManager.show("Stream error: \(error.localizedDescription)", style: .error)
                    }
                }
            }
            streamingTask = task
            await task.value

            isStreaming = false
            streamingContent = ""
            streamingTask = nil

            // Save to server
            if let convId = selectedConversationID {
                messageCache[convId] = chatMessages
                let fallbackTitle = chatMessages.first(where: { $0.role == "user" })
                    .map { String($0.content.prefix(100)) } ?? "New Chat"
                let blob = buildChatBlob(title: fallbackTitle, assistantId: nil, assistantModel: nil)
                Task {
                    _ = try? await client.updateChat(id: convId, blob: blob)
                }
            }
        } else {
            // Just save the edit without re-streaming
            if let convId = selectedConversationID {
                messageCache[convId] = chatMessages
                if let client {
                    let fallbackTitle = chatMessages.first(where: { $0.role == "user" })
                        .map { String($0.content.prefix(100)) } ?? "New Chat"
                    let blob = buildChatBlob(title: fallbackTitle, assistantId: nil, assistantModel: nil)
                    Task {
                        _ = try? await client.updateChat(id: convId, blob: blob)
                    }
                }
            }
        }
    }

    // MARK: - Regenerate Response

    /// Regenerate the last assistant response from a given message.
    /// Removes the assistant message and re-streams.
    func regenerateResponse(messageId: String) async {
        guard let idx = chatMessages.firstIndex(where: { $0.id == messageId }) else { return }
        let message = chatMessages[idx]
        guard message.role == "assistant" else { return }
        guard !isStreaming else { return }

        // Remove the assistant message and any messages after it
        chatMessages = Array(chatMessages.prefix(idx))

        guard let model = selectedModel, let client else { return }

        let assistantId = UUID().uuidString
        isStreaming = true
        streamingContent = ""

        let assistantMsg = ChatMessage(
            id: assistantId,
            role: "assistant",
            content: "",
            model: model.id,
            timestamp: Date().timeIntervalSince1970,
            parentId: chatMessages.last?.id,
            childrenIds: nil
        )
        chatMessages.append(assistantMsg)

        let completionMsgs = Self.buildCompletionMessages(from: Array(chatMessages.dropLast()))

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stream = await client.streamChat(
                    model: model.id,
                    messages: completionMsgs,
                    files: nil,
                    webSearch: self.isWebSearchEnabled
                )
                var toolCallAccumulator: [Int: (id: String, type: String, name: String, arguments: String)] = [:]

                for try await delta in stream {
                    if Task.isCancelled { break }
                    switch delta {
                    case .content(let text):
                        self.streamingContent += text
                    case .toolCall(let tc):
                        let tcIdx = tc.index ?? 0
                        var entry = toolCallAccumulator[tcIdx] ?? (id: "", type: "function", name: "", arguments: "")
                        if let id = tc.id { entry.id = id }
                        if let type = tc.type { entry.type = type }
                        if let name = tc.function?.name { entry.name += name }
                        if let args = tc.function?.arguments { entry.arguments += args }
                        toolCallAccumulator[tcIdx] = entry
                    case .done:
                        break
                    }

                    var completedToolCalls: [ToolCall] = toolCallAccumulator.sorted(by: { $0.key < $1.key }).compactMap { (_, entry) in
                        guard !entry.id.isEmpty, !entry.name.isEmpty else { return nil }
                        return ToolCall(id: entry.id, type: entry.type, function: ToolCall.ToolCallComplete(name: entry.name, arguments: entry.arguments), status: .executing)
                    }
                    let parsedFromContent = Self.parseToolCallDetails(from: self.streamingContent)
                    for parsed in parsedFromContent {
                        if let i = completedToolCalls.firstIndex(where: { $0.id == parsed.id }) {
                            completedToolCalls[i] = parsed
                        } else if !completedToolCalls.contains(where: { $0.id == parsed.id }) {
                            completedToolCalls.append(parsed)
                        }
                    }

                    if let idx = self.chatMessages.lastIndex(where: { $0.id == assistantId }) {
                        var updated = ChatMessage(
                            id: assistantId,
                            role: "assistant",
                            content: self.streamingContent,
                            model: model.id,
                            timestamp: Date().timeIntervalSince1970,
                            parentId: self.chatMessages.count >= 2 ? self.chatMessages[self.chatMessages.count - 2].id : nil,
                            childrenIds: nil
                        )
                        if !completedToolCalls.isEmpty { updated.toolCalls = completedToolCalls }
                        // Preserve statusHistory from Socket.IO events
                        updated.statusHistory = self.chatMessages[idx].statusHistory
                        self.chatMessages[idx] = updated
                    }
                }

                // Finalize tool call statuses
                if let idx = self.chatMessages.lastIndex(where: { $0.id == assistantId }) {
                    var finalMsg = self.chatMessages[idx]
                    if var toolCalls = finalMsg.toolCalls {
                        for i in toolCalls.indices where toolCalls[i].status == .executing || toolCalls[i].status == .pending {
                            toolCalls[i].status = .completed
                        }
                        finalMsg.toolCalls = toolCalls
                        self.chatMessages[idx] = finalMsg
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.toastManager.show("Stream error: \(error.localizedDescription)", style: .error)
                }
            }
        }
        streamingTask = task
        await task.value

        isStreaming = false
        streamingContent = ""
        streamingTask = nil

        // Save to server
        if let convId = selectedConversationID {
            messageCache[convId] = chatMessages
            let fallbackTitle = chatMessages.first(where: { $0.role == "user" })
                .map { String($0.content.prefix(100)) } ?? "New Chat"
            let blob = buildChatBlob(title: fallbackTitle, assistantId: nil, assistantModel: nil)
            Task {
                _ = try? await client.updateChat(id: convId, blob: blob)
            }
        }
        Task { await loadConversations(silent: true) }
    }

    // MARK: - Text-to-Speech

    /// Speak assistant message content.
    /// Uses RunAnywhere on-device TTS if loaded, otherwise falls back to macOS native TTS.
    /// Strips reasoning/thinking blocks before speaking.
    func speakMessage(_ content: String) {
        let cleaned = stripReasoningBlocks(content)
        if RunAnywhereService.shared.ttsModelState == .loaded {
            // Use on-device RunAnywhere TTS (much better quality)
            ttsManager.speakWithRunAnywhere(cleaned)
        } else {
            ttsManager.speak(cleaned)
        }
    }

    func stopSpeaking() {
        ttsManager.stop()
    }

    /// Strip <details type="reasoning">...</details> blocks from content
    /// so TTS doesn't read the thinking process.
    private func stripReasoningBlocks(_ content: String) -> String {
        // Pattern: <details type="reasoning"...>...</details>
        var result = content
        while let startRange = result.range(of: "<details[^>]*type=\"reasoning\"[^>]*>", options: .regularExpression) {
            if let endRange = result.range(of: "</details>", range: startRange.upperBound..<result.endIndex) {
                result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                // Unclosed tag — remove from start to end
                result.removeSubrange(startRange.lowerBound..<result.endIndex)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tool Call Details Parser

    /// Parse `<details type="tool_calls" ...>` blocks from message content.
    /// Open WebUI embeds tool call results as HTML details tags in the streaming content.
    static func parseToolCallDetails(from content: String) -> [ToolCall] {
        var toolCalls: [ToolCall] = []

        // Match both closed and unclosed (in-progress) tool call details
        let closedPattern = #"<details[^>]*type="tool_calls"([^>]*)>[\s\S]*?</details>"#
        let unclosedPattern = #"<details[^>]*type="tool_calls"([^>]*)>[\s\S]*?$"#

        for pattern in [closedPattern, unclosedPattern] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let nsContent = content as NSString
            let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))

            for match in matches {
                let attrsRange = match.range(at: 1)
                let attrs = nsContent.substring(with: attrsRange)

                // Extract attributes
                let id = extractAttribute("id", from: attrs) ?? UUID().uuidString
                let name = extractAttribute("name", from: attrs) ?? "unknown"
                let arguments = htmlDecode(extractAttribute("arguments", from: attrs) ?? "{}")
                let result = extractAttribute("result", from: attrs).map { htmlDecode($0) }
                let isDone = attrs.contains(#"done="true""#)

                let status: ToolCallStatus = isDone ? .completed : .executing
                let toolCall = ToolCall(
                    id: id,
                    type: "function",
                    function: ToolCall.ToolCallComplete(name: name, arguments: arguments),
                    status: status,
                    result: result
                )
                // Avoid duplicates
                if !toolCalls.contains(where: { $0.id == toolCall.id }) {
                    toolCalls.append(toolCall)
                }
            }
            // If we found closed matches, don't also look for unclosed
            if !toolCalls.isEmpty && pattern == closedPattern { break }
        }

        return toolCalls
    }

    /// Extract an HTML attribute value from an attributes string.
    private static func extractAttribute(_ name: String, from attrs: String) -> String? {
        let pattern = name + #"="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: attrs, range: NSRange(location: 0, length: (attrs as NSString).length)) else {
            return nil
        }
        return (attrs as NSString).substring(with: match.range(at: 1))
    }

    /// Basic HTML entity decoding for tool call attributes.
    private static func htmlDecode(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
    }

    /// Strip `<details type="tool_calls">` blocks from content for display,
    /// since tool calls are rendered separately in the UI.
    static func stripToolCallDetails(from content: String) -> String {
        var result = content
        // Closed blocks
        while let startRange = result.range(of: #"<details[^>]*type="tool_calls"[^>]*>"#, options: .regularExpression) {
            if let endRange = result.range(of: "</details>", range: startRange.upperBound..<result.endIndex) {
                result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                result.removeSubrange(startRange.lowerBound..<result.endIndex)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Completion Message Builder

    /// Build completion messages from chat messages, including tool call context.
    /// This ensures tool calls and tool results are properly represented in the
    /// OpenAI-compatible format when sent to the server.
    static func buildCompletionMessages(from messages: [ChatMessage]) -> [CompletionMessage] {
        var result: [CompletionMessage] = []
        for msg in messages {
            // Strip tool call details HTML from content for the API payload
            let cleanContent = stripToolCallDetails(from: msg.content)

            if msg.role == "assistant", let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                // Assistant message with tool calls — include them in OpenAI format
                let apiToolCalls = toolCalls.map { tc in
                    CompletionToolCall(
                        id: tc.id,
                        type: tc.type,
                        function: CompletionToolCallFunction(name: tc.function.name, arguments: tc.function.arguments)
                    )
                }
                if let images = msg.images, !images.isEmpty {
                    var parts: [ContentPart] = []
                    if !cleanContent.isEmpty { parts.append(.text(cleanContent)) }
                    for img in images { parts.append(.imageURL(img)) }
                    result.append(CompletionMessage(role: msg.role, content: .parts(parts), tool_calls: apiToolCalls))
                } else {
                    result.append(CompletionMessage(role: msg.role, content: .text(cleanContent), tool_calls: apiToolCalls))
                }
            } else if msg.role == "tool" {
                // Tool result message — include tool_call_id
                result.append(CompletionMessage(role: "tool", content: .text(cleanContent), tool_call_id: msg.toolCallId))
            } else {
                // Regular message (user, system, assistant without tool calls)
                if let images = msg.images, !images.isEmpty {
                    var parts: [ContentPart] = []
                    if !cleanContent.isEmpty { parts.append(.text(cleanContent)) }
                    for img in images { parts.append(.imageURL(img)) }
                    result.append(CompletionMessage(role: msg.role, content: .parts(parts)))
                } else {
                    result.append(CompletionMessage(role: msg.role, content: .text(cleanContent)))
                }
            }
        }
        return result
    }

    // MARK: - Mini Chat

    /// Send a message in the mini chat window. This is a lightweight version
    /// that doesn't persist to the server — it's for quick one-off queries.
    func sendMiniMessage() async {
        // Route to demo handler if in demo mode
        if isDemoMode {
            await sendMiniDemoMessage()
            return
        }

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

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stream = await client.streamChat(
                    model: model.id,
                    messages: completionMsgs,
                    files: nil,
                    webSearch: false
                )
                for try await delta in stream {
                    if Task.isCancelled { break }
                    switch delta {
                    case .content(let text):
                        self.miniStreamingContent += text
                    case .toolCall:
                        // Mini chat doesn't display tool calls
                        break
                    case .done:
                        break
                    }
                    if let idx = self.miniChatMessages.lastIndex(where: { $0.id == assistantId }) {
                        self.miniChatMessages[idx] = ChatMessage(
                            id: assistantId,
                            role: "assistant",
                            content: self.miniStreamingContent,
                            model: model.id,
                            timestamp: Date().timeIntervalSince1970,
                            parentId: userMsg.id,
                            childrenIds: nil
                        )
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.toastManager.show("Stream error: \(error.localizedDescription)", style: .error)
                }
            }
        }
        miniStreamingTask = task
        await task.value

        isMiniStreaming = false
        miniStreamingContent = ""
        miniStreamingTask = nil
    }

    func stopMiniStreaming() {
        miniStreamingTask?.cancel()
        miniStreamingTask = nil
        isMiniStreaming = false
        miniStreamingContent = ""
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

    // MARK: - Demo Mode Logic

    /// Enter demo mode: populate the app with mock data so reviewers can see
    /// the full UI without connecting to a real server.
    func enterDemoMode() {
        isDemoMode = true

        // Mock server
        let demoServer = ServerConfig(
            name: "Demo Server",
            url: "https://demo.openwebui.local",
            apiKey: "demo-key",
            authMethod: .apiKey,
            email: nil,
            iconEmoji: "🧪"
        )
        servers = [demoServer]
        activeServerID = demoServer.id
        serverURL = demoServer.url
        serverReachable = true
        serverVersion = "0.5.1"

        // Mock user
        currentUser = SessionUser(
            token: nil,
            id: "demo-user",
            email: "reviewer@apple.com",
            name: "App Reviewer",
            role: "user",
            profile_image_url: nil
        )

        // Mock models
        models = [
            AIModel(id: "llama3.2:latest", name: "Llama 3.2", owned_by: "meta"),
            AIModel(id: "gpt-4o", name: "GPT-4o", owned_by: "openai"),
            AIModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", owned_by: "anthropic"),
            AIModel(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", owned_by: "google"),
            AIModel(id: "mistral-large", name: "Mistral Large", owned_by: "mistral"),
            AIModel(id: "deepseek-r1:latest", name: "DeepSeek R1", owned_by: "deepseek"),
        ]
        selectedModel = models[0]

        // Mock conversations with realistic timestamps
        let now = Date().timeIntervalSince1970
        let hour: Double = 3600
        let day: Double = 86400

        conversations = [
            ChatListItem(id: "demo-1", title: "🧮 Explain quantum computing basics", updated_at: now - 0.5 * hour, created_at: now - 1 * hour),
            ChatListItem(id: "demo-2", title: "🍳 Quick pasta recipe for dinner", updated_at: now - 2 * hour, created_at: now - 3 * hour),
            ChatListItem(id: "demo-3", title: "🐍 Python async/await best practices", updated_at: now - 1 * day, created_at: now - 1 * day),
            ChatListItem(id: "demo-4", title: "📝 Draft email to client about project", updated_at: now - 1.5 * day, created_at: now - 2 * day),
            ChatListItem(id: "demo-5", title: "🎨 SwiftUI animation techniques", updated_at: now - 3 * day, created_at: now - 3 * day),
            ChatListItem(id: "demo-6", title: "🌍 Climate change impact on oceans", updated_at: now - 5 * day, created_at: now - 5 * day),
            ChatListItem(id: "demo-7", title: "🎵 Music theory for beginners", updated_at: now - 10 * day, created_at: now - 10 * day),
            ChatListItem(id: "demo-8", title: "🚀 How to deploy with Docker", updated_at: now - 15 * day, created_at: now - 15 * day),
            ChatListItem(id: "demo-9", title: "📊 SQL query optimization tips", updated_at: now - 35 * day, created_at: now - 35 * day),
            ChatListItem(id: "demo-10", title: "✈️ Planning a trip to Japan", updated_at: now - 45 * day, created_at: now - 45 * day),
        ]

        // Populate message cache for each conversation
        populateDemoMessages()

        // Select the first conversation and show its messages
        selectedConversationID = "demo-1"
        chatMessages = demoMessageSets["demo-1"] ?? []

        // Navigate to chat
        currentScreen = .chat
    }

    /// Populate demo message cache with realistic multi-turn conversations.
    private func populateDemoMessages() {
        let model = "llama3.2:latest"
        let now = Date().timeIntervalSince1970

        // -- Conversation 1: Quantum computing
        let q1: [ChatMessage] = [
            ChatMessage(id: "d1-1", role: "user", content: "Can you explain quantum computing in simple terms?", model: nil, timestamp: now - 3600, parentId: nil, childrenIds: ["d1-2"]),
            ChatMessage(id: "d1-2", role: "assistant", content: """
            Of course! Here's a simple breakdown:

            ## Classical vs Quantum

            **Classical computers** use **bits** — each bit is either `0` or `1`. Think of it like a light switch: on or off.

            **Quantum computers** use **qubits** (quantum bits). Thanks to a property called **superposition**, a qubit can be `0`, `1`, or *both at the same time*. This lets quantum computers explore many possibilities simultaneously.

            ## Key Concepts

            1. **Superposition** — A qubit exists in multiple states until measured
            2. **Entanglement** — Two qubits can be linked so measuring one instantly affects the other, regardless of distance
            3. **Interference** — Quantum algorithms amplify correct answers and cancel wrong ones

            ## Why It Matters

            Quantum computers excel at:
            - **Cryptography** — Breaking and creating encryption
            - **Drug discovery** — Simulating molecular interactions
            - **Optimization** — Finding the best solution among billions of options
            - **Machine learning** — Training complex models faster

            > Think of it this way: if a classical computer tries every path in a maze one by one, a quantum computer explores all paths at once.

            It's still early days — most quantum computers need extreme cooling (near absolute zero) and are prone to errors. But progress is accelerating rapidly!
            """, model: model, timestamp: now - 3500, parentId: "d1-1", childrenIds: ["d1-3"]),
            ChatMessage(id: "d1-3", role: "user", content: "What's the difference between a qubit and a classical bit in terms of information capacity?", model: nil, timestamp: now - 3400, parentId: "d1-2", childrenIds: ["d1-4"]),
            ChatMessage(id: "d1-4", role: "assistant", content: """
            Great question! Here's the key difference:

            | Property | Classical Bit | Qubit |
            |----------|--------------|-------|
            | States | 0 or 1 | 0, 1, or superposition |
            | Info per unit | 1 bit | Up to 2 classical bits* |
            | N units encode | N bits | 2^N amplitudes |

            With **3 classical bits**, you can represent one of 8 values (000, 001, ..., 111).

            With **3 qubits**, you can represent all 8 values *simultaneously* as a superposition. That's the power — it scales exponentially:

            ```
            1 qubit  →  2 states
            10 qubits → 1,024 states
            50 qubits → 1,125,899,906,842,624 states
            ```

            *However*, when you measure a qubit, it collapses to a single value. The trick is designing algorithms that guide the superposition toward the correct answer before measurement.
            """, model: model, timestamp: now - 3300, parentId: "d1-3", childrenIds: nil),
        ]

        // -- Conversation 2: Pasta recipe
        let q2: [ChatMessage] = [
            ChatMessage(id: "d2-1", role: "user", content: "What's a quick and easy pasta recipe I can make in 20 minutes?", model: nil, timestamp: now - 7200, parentId: nil, childrenIds: ["d2-2"]),
            ChatMessage(id: "d2-2", role: "assistant", content: """
            Here's my go-to **Garlic Butter Pasta with Lemon and Parmesan** — ready in 15 minutes!

            ### Ingredients
            - 300g spaghetti (or any pasta)
            - 4 cloves garlic, thinly sliced
            - 3 tbsp butter
            - 2 tbsp olive oil
            - Juice of 1 lemon
            - 1/2 cup grated Parmesan
            - Red pepper flakes (optional)
            - Fresh basil or parsley
            - Salt & black pepper

            ### Steps

            1. **Cook pasta** in salted boiling water until al dente. Reserve 1 cup pasta water before draining.
            2. **Sauté garlic** in butter + olive oil over medium heat until golden (~2 min). Don't burn it!
            3. **Combine** — Toss drained pasta into the pan. Add lemon juice, 1/2 cup pasta water, and Parmesan.
            4. **Toss** until creamy. Add more pasta water if needed.
            5. **Finish** with pepper flakes, fresh herbs, and extra Parmesan.

            > **Pro tip:** The starchy pasta water is what makes the sauce silky. Don't skip it!

            Pairs well with a simple side salad. Enjoy! 🍝
            """, model: model, timestamp: now - 7100, parentId: "d2-1", childrenIds: nil),
        ]

        // -- Conversation 3: Python async
        let q3: [ChatMessage] = [
            ChatMessage(id: "d3-1", role: "user", content: "What are the best practices for using async/await in Python?", model: nil, timestamp: now - 86400, parentId: nil, childrenIds: ["d3-2"]),
            ChatMessage(id: "d3-2", role: "assistant", content: """
            Here are the key best practices for Python's `async`/`await`:

            ## 1. Use `asyncio.run()` as your entry point

            ```python
            import asyncio

            async def main():
                result = await fetch_data()
                print(result)

            asyncio.run(main())
            ```

            ## 2. Use `asyncio.gather()` for concurrent tasks

            ```python
            async def fetch_all():
                results = await asyncio.gather(
                    fetch_users(),
                    fetch_posts(),
                    fetch_comments(),
                )
                return results
            ```

            ## 3. Avoid blocking calls in async code

            Never use `time.sleep()` or synchronous I/O in async functions. Use `await asyncio.sleep()` and async-compatible libraries like `aiohttp`, `asyncpg`, etc.

            ## 4. Use `async with` for resource management

            ```python
            async with aiohttp.ClientSession() as session:
                async with session.get(url) as resp:
                    data = await resp.json()
            ```

            ## 5. Handle exceptions properly

            ```python
            try:
                results = await asyncio.gather(
                    task1(), task2(),
                    return_exceptions=True
                )
            except Exception as e:
                logging.error(f"Task failed: {e}")
            ```

            The main takeaway: **async is for I/O-bound work** (network, disk, DB). For CPU-bound work, use `multiprocessing` or `concurrent.futures`.
            """, model: model, timestamp: now - 86300, parentId: "d3-1", childrenIds: nil),
        ]

        // -- Conversation 5: SwiftUI animations
        let q5: [ChatMessage] = [
            ChatMessage(id: "d5-1", role: "user", content: "What are some cool SwiftUI animation techniques?", model: nil, timestamp: now - 259200, parentId: nil, childrenIds: ["d5-2"]),
            ChatMessage(id: "d5-2", role: "assistant", content: """
            SwiftUI has a powerful animation system. Here are some standout techniques:

            ## 1. Matched Geometry Effect
            Creates smooth transitions between views sharing an identity:
            ```swift
            @Namespace var animation

            // Source view
            Circle()
                .matchedGeometryEffect(id: "shape", in: animation)

            // Destination view
            Rectangle()
                .matchedGeometryEffect(id: "shape", in: animation)
            ```

            ## 2. Phase Animator (iOS 17+)
            Multi-step animations without timers:
            ```swift
            PhaseAnimator([false, true]) { phase in
                Image(systemName: "star.fill")
                    .scaleEffect(phase ? 1.5 : 1.0)
                    .rotationEffect(.degrees(phase ? 360 : 0))
            }
            ```

            ## 3. Spring Animations
            Natural-feeling motion:
            ```swift
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                isExpanded.toggle()
            }
            ```

            ## 4. Keyframe Animator (iOS 17+)
            Fine-grained control over timing:
            ```swift
            KeyframeAnimator(initialValue: AnimationValues()) { values in
                content
                    .scaleEffect(values.scale)
                    .offset(y: values.yOffset)
            } keyframes: { _ in
                KeyframeTrack(\\.scale) {
                    SpringKeyframe(1.2, duration: 0.2)
                    SpringKeyframe(1.0, duration: 0.3)
                }
            }
            ```

            These make SwiftUI apps feel incredibly polished!
            """, model: model, timestamp: now - 259100, parentId: "d5-1", childrenIds: nil),
        ]

        demoMessageSets = [
            "demo-1": q1,
            "demo-2": q2,
            "demo-3": q3,
            "demo-5": q5,
        ]

        // Store in message cache for instant switching
        for (id, msgs) in demoMessageSets {
            messageCache[id] = msgs
        }
    }

    /// Stored demo message sets keyed by conversation ID.
    private var demoMessageSets: [String: [ChatMessage]] = [:]

    // MARK: - Demo Responses

    /// Pre-written demo responses for common questions. The app picks one based on keywords
    /// and simulates streaming it character-by-character.
    private static let demoResponses: [(keywords: [String], response: String)] = [
        (["hello", "hi", "hey", "greet"], """
        Hello! 👋 Welcome to **Oval** — a native macOS client for Open WebUI.

        I'm a demo assistant running in offline mode. Here are some things you can try:

        - Ask me about **programming**, **science**, or **recipes**
        - Test the **model selector** in the toolbar
        - Toggle **dark/light mode** in System Settings
        - Try the **keyboard shortcuts** (Cmd+N for new chat)
        - Open **Settings** with Cmd+,

        How can I help you today?
        """),
        (["swift", "swiftui", "ios", "apple", "xcode"], """
        Great question about Swift development! Here's a quick overview:

        ## SwiftUI Essentials

        SwiftUI is Apple's declarative framework for building user interfaces. Key concepts:

        1. **Views are structs** — lightweight and efficient
        2. **State management** — `@State`, `@Binding`, `@Observable`
        3. **Modifiers chain** — `.padding().background().cornerRadius()`

        ```swift
        struct ContentView: View {
            @State private var count = 0

            var body: some View {
                VStack {
                    Text("Count: \\(count)")
                        .font(.title)
                    Button("Increment") {
                        count += 1
                    }
                }
            }
        }
        ```

        > **Tip:** Use `#Preview` macros in Xcode for instant visual feedback.

        SwiftUI works across all Apple platforms — iOS, macOS, watchOS, tvOS, and visionOS.
        """),
        (["python", "code", "programming", "javascript", "rust"], """
        Here's a quick programming tip!

        ## Clean Code Principles

        1. **Single Responsibility** — Each function does one thing well
        2. **Meaningful Names** — `calculateTotalPrice()` not `calc()`
        3. **DRY** — Don't Repeat Yourself

        ```python
        # Bad
        def process(d):
            r = []
            for i in d:
                if i > 0:
                    r.append(i * 2)
            return r

        # Good
        def double_positive_values(numbers: list[int]) -> list[int]:
            return [n * 2 for n in numbers if n > 0]
        ```

        | Principle | Benefit |
        |-----------|---------|
        | SOLID | Maintainable architecture |
        | KISS | Reduced complexity |
        | YAGNI | Less unused code |

        Remember: **readable code is maintainable code**.
        """),
        (["weather", "climate", "temperature", "rain"], """
        ## Understanding Weather Patterns

        Weather is the short-term state of the atmosphere. Key factors:

        - **Temperature** — Driven by solar radiation and altitude
        - **Pressure** — High pressure → clear skies, low pressure → storms
        - **Humidity** — Water vapor content in the air
        - **Wind** — Caused by pressure differences

        ### Fun Facts
        - Lightning strikes Earth ~100 times per second ⚡
        - A hurricane releases energy equivalent to 10,000 nuclear bombs per day
        - The highest temperature ever recorded was 56.7°C (134°F) in Death Valley

        > Weather forecasting uses massive computational models processing billions of data points from satellites, weather stations, and ocean buoys.
        """),
        (["math", "calculus", "equation", "number", "algebra"], """
        ## Quick Math Refresher

        ### The Quadratic Formula
        For any equation $ax^2 + bx + c = 0$:

        ```
        x = (-b ± √(b² - 4ac)) / 2a
        ```

        ### Example
        Solve: `x² - 5x + 6 = 0`

        - a=1, b=-5, c=6
        - Discriminant: 25 - 24 = 1
        - x = (5 ± 1) / 2
        - **x = 3** or **x = 2**

        ### Key Identities
        | Identity | Formula |
        |----------|---------|
        | Pythagorean | a² + b² = c² |
        | Euler's | e^(iπ) + 1 = 0 |
        | Sum of n | n(n+1)/2 |

        Mathematics is the language of the universe! 🔢
        """),
    ]

    /// Default fallback response for demo mode.
    private static let defaultDemoResponse = """
    That's an interesting question! Let me share some thoughts:

    ## Key Points

    1. **Context matters** — The best answer depends on your specific situation
    2. **Research is key** — I'd recommend looking into authoritative sources
    3. **Iterate** — Start with a simple approach and refine

    Here's a general framework for thinking about problems:

    ```
    1. Define the problem clearly
    2. Break it into smaller parts
    3. Solve each part independently
    4. Combine and verify the solution
    ```

    ### Additional Resources
    - Documentation and official guides
    - Community forums and discussions
    - Hands-on experimentation

    > **Note:** This is a demo response. In a real session connected to your Open WebUI server, you'd get responses from your configured AI models (Llama, GPT-4, Claude, etc.).

    Would you like me to elaborate on any of these points?
    """

    /// Send a message in demo mode with simulated streaming.
    func sendDemoMessage() async {
        let text = messageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard let model = selectedModel else { return }

        let isNewConversation = selectedConversationID == nil

        // Add user message
        let userMsg = ChatMessage(
            id: UUID().uuidString,
            role: "user",
            content: text,
            model: nil,
            timestamp: Date().timeIntervalSince1970,
            parentId: chatMessages.last?.id,
            childrenIds: nil
        )
        chatMessages.append(userMsg)
        messageInput = ""
        pendingAttachments = []

        // If new conversation, create a mock one and add to sidebar
        if isNewConversation {
            let title = String(text.prefix(50))
            let newId = UUID().uuidString
            let newConvo = ChatListItem(
                id: newId,
                title: "💬 \(title)",
                updated_at: Date().timeIntervalSince1970,
                created_at: Date().timeIntervalSince1970
            )
            conversations.insert(newConvo, at: 0)
            suppressConversationSelection = true
            selectedConversationID = newId
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                suppressConversationSelection = false
            }
        }

        // Pick a response based on keywords
        let lowerText = text.lowercased()
        let response = Self.demoResponses.first(where: { pair in
            pair.keywords.contains(where: { lowerText.contains($0) })
        })?.response ?? Self.defaultDemoResponse

        // Simulate streaming
        let assistantId = UUID().uuidString
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

        // Stream character by character with variable speed
        for char in response {
            // Check if streaming was cancelled
            guard isStreaming else { break }

            streamingContent += String(char)

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

            // Variable typing speed: faster for spaces, slower for newlines
            let delay: UInt64
            if char == "\n" {
                delay = 15_000_000   // 15ms for newlines
            } else if char == " " {
                delay = 5_000_000    // 5ms for spaces
            } else {
                delay = 8_000_000    // 8ms per character
            }
            try? await Task.sleep(nanoseconds: delay)
        }

        isStreaming = false
        streamingContent = ""

        // Update cache
        if let convId = selectedConversationID {
            messageCache[convId] = chatMessages
        }
    }

    /// Send a message in the mini chat in demo mode with simulated streaming.
    func sendMiniDemoMessage() async {
        let text = miniMessageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isMiniStreaming else { return }
        guard let model = selectedModel else { return }

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

        let lowerText = text.lowercased()
        let response = Self.demoResponses.first(where: { pair in
            pair.keywords.contains(where: { lowerText.contains($0) })
        })?.response ?? Self.defaultDemoResponse

        let assistantId = UUID().uuidString
        isMiniStreaming = true
        miniStreamingContent = ""

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

        for char in response {
            guard isMiniStreaming else { break }
            miniStreamingContent += String(char)
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
            let delay: UInt64 = char == "\n" ? 15_000_000 : (char == " " ? 5_000_000 : 8_000_000)
            try? await Task.sleep(nanoseconds: delay)
        }

        isMiniStreaming = false
        miniStreamingContent = ""
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
