import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers
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

    // MARK: - Model Preferences

    /// The user's explicit default model ID (persisted in config).
    var defaultModelID: String?

    /// Pinned/favorite model IDs shown in the sidebar (persisted in config).
    var pinnedModelIDs: [String] = []

    /// Internal: persisted selected model ID loaded from config (used in loadModels to restore selection).
    private var _persistedSelectedModelID: String?
    /// Internal: persisted default model ID loaded from config.
    private var _persistedDefaultModelID: String?

    /// Computed: pinned models resolved from the current model list.
    var pinnedModels: [AIModel] {
        pinnedModelIDs.compactMap { id in models.first { $0.id == id } }
    }

    /// Whether a model is pinned.
    func isModelPinned(_ model: AIModel) -> Bool {
        pinnedModelIDs.contains(model.id)
    }

    /// Toggle pin state for a model.
    func togglePinModel(_ model: AIModel) {
        if let idx = pinnedModelIDs.firstIndex(of: model.id) {
            pinnedModelIDs.remove(at: idx)
        } else {
            pinnedModelIDs.append(model.id)
        }
        saveModelPreferences()
    }

    /// Set the default model.
    func setDefaultModel(_ model: AIModel?) {
        defaultModelID = model?.id
        saveModelPreferences()
    }

    /// Whether a model is the user's default.
    func isDefaultModel(_ model: AIModel) -> Bool {
        defaultModelID == model.id
    }

    // MARK: - Chat

    var chatMessages: [ChatMessage] = []
    var selectedModel: AIModel? {
        didSet {
            // Persist whenever the user changes model selection
            if selectedModel?.id != oldValue?.id {
                saveModelPreferences()
            }
        }
    }
    var messageInput: String = ""

    /// Per-conversation streaming state: set of chat IDs that are currently streaming.
    var streamingChatIDs: Set<String> = []

    /// Per-conversation streaming content (accumulated text for the assistant response).
    var streamingContentByChat: [String: String] = [:]

    /// Per-conversation streaming tasks — keyed by chat ID.
    private var streamingTaskByChat: [String: Task<Void, Never>] = [:]

    /// Per-conversation streaming message IDs (for Socket.IO event routing).
    private var streamingMessageIdByChat: [String: String] = [:]

    /// Per-conversation watchdog timers that detect stalled streams.
    /// If no events arrive within the timeout, streaming is ended gracefully.
    private var watchdogTimerByChat: [String: Task<Void, Never>] = [:]

    /// Watchdog timeout in seconds — if no streaming event arrives within this period, end the stream.
    private let streamWatchdogTimeout: TimeInterval = 90

    /// Per-conversation cached messages — used when user switches away from a streaming chat.
    /// The streaming task updates this instead of `chatMessages` when the user navigates away.
    private var streamingMessagesCache: [String: [ChatMessage]] = [:]

    /// Convenience: whether the *currently viewed* conversation is streaming.
    var isStreaming: Bool {
        guard let id = selectedConversationID else { return false }
        return streamingChatIDs.contains(id)
    }

    /// Convenience: streaming content for the *currently viewed* conversation.
    var streamingContent: String {
        get {
            guard let id = selectedConversationID else { return "" }
            return streamingContentByChat[id] ?? ""
        }
        set {
            guard let id = selectedConversationID else { return }
            streamingContentByChat[id] = newValue
        }
    }

    // MARK: - Per-Conversation Streaming Helpers

    /// Start streaming for a specific conversation.
    private func beginStreaming(chatId: String) {
        streamingChatIDs.insert(chatId)
        streamingContentByChat[chatId] = ""
        startWatchdog(chatId: chatId)
    }

    /// End streaming for a specific conversation.
    private func endStreaming(chatId: String) {
        streamingChatIDs.remove(chatId)
        streamingContentByChat.removeValue(forKey: chatId)
        streamingTaskByChat.removeValue(forKey: chatId)
        streamingMessageIdByChat.removeValue(forKey: chatId)
        streamingMessagesCache.removeValue(forKey: chatId)
        cancelWatchdog(chatId: chatId)
    }

    /// Stop streaming for the currently viewed conversation.
    func stopStreaming() {
        guard let chatId = selectedConversationID else { return }
        stopStreaming(chatId: chatId)
    }

    /// Stop streaming for a specific conversation.
    func stopStreaming(chatId: String) {
        streamingTaskByChat[chatId]?.cancel()
        endStreaming(chatId: chatId)
    }

    // MARK: - Stream Watchdog

    /// Start a watchdog timer for a streaming conversation.
    /// If no events arrive within `streamWatchdogTimeout`, the stream is ended gracefully.
    private func startWatchdog(chatId: String) {
        cancelWatchdog(chatId: chatId)
        watchdogTimerByChat[chatId] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.streamWatchdogTimeout ?? 90))
            guard !Task.isCancelled else { return }
            guard let self, self.streamingChatIDs.contains(chatId) else { return }
            ovalLog.warning("[Oval] Stream watchdog fired for chat \(chatId) — ending stalled stream")
            self.toastManager.show("Response timed out", style: .warning)
            self.stopStreaming(chatId: chatId)
        }
    }

    /// Reset the watchdog timer (called on every incoming streaming event).
    private func resetWatchdog(chatId: String) {
        guard streamingChatIDs.contains(chatId) else { return }
        startWatchdog(chatId: chatId)
    }

    /// Cancel the watchdog timer for a conversation.
    private func cancelWatchdog(chatId: String) {
        watchdogTimerByChat[chatId]?.cancel()
        watchdogTimerByChat.removeValue(forKey: chatId)
    }

    // MARK: - Reconnection Recovery

    /// After a socket reconnection, poll the server for the current chat state.
    /// If the server has longer content for the streaming assistant message, adopt it.
    /// This recovers content that was missed during the disconnection.
    private func attemptReconnectionRecovery(chatId: String) {
        guard let client else { return }
        guard let streamingMsgId = streamingMessageIdByChat[chatId] else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Wait briefly for the server to process any pending events
            try? await Task.sleep(for: .milliseconds(500))
            guard self.streamingChatIDs.contains(chatId) else { return }

            do {
                let chatResponse = try await client.getChat(id: chatId)
                guard let history = chatResponse.chat?.history else { return }
                let serverMessages = history.linearMessages()

                // Find the streaming assistant message on the server
                guard let serverMsg = serverMessages.last(where: { $0.id == streamingMsgId }) else { return }

                // Compare content length — adopt server's content if it's longer
                let localContent = self.streamingContentByChat[chatId] ?? ""
                if serverMsg.content.count > localContent.count {
                    ovalLog.info("[Oval] Reconnection recovery: adopting server content (\(serverMsg.content.count) chars vs local \(localContent.count) chars)")
                    self.streamingContentByChat[chatId] = serverMsg.content

                    // Update the local message
                    var messages = self.getStreamingMessages(chatId: chatId)
                    if let idx = messages.lastIndex(where: { $0.id == streamingMsgId }) {
                        var updated = messages[idx]
                        updated = ChatMessage(
                            id: updated.id,
                            role: updated.role,
                            content: serverMsg.content,
                            model: updated.model,
                            timestamp: updated.timestamp,
                            parentId: updated.parentId,
                            childrenIds: updated.childrenIds
                        )
                        updated.toolCalls = messages[idx].toolCalls
                        updated.statusHistory = messages[idx].statusHistory
                        updated.sources = messages[idx].sources
                        updated.codeExecutions = messages[idx].codeExecutions
                        updated.followUps = messages[idx].followUps
                        updated.usage = messages[idx].usage
                        updated.messageError = messages[idx].messageError
                        messages[idx] = updated
                        self.setStreamingMessages(chatId: chatId, messages: messages)
                    }
                }
            } catch {
                ovalLog.warning("[Oval] Reconnection recovery failed for chat \(chatId): \(error.localizedDescription)")
            }
        }
    }

    /// Whether a specific conversation is streaming (for sidebar indicators).
    func isChatStreaming(_ chatId: String) -> Bool {
        streamingChatIDs.contains(chatId)
    }

    /// Get or update messages for a streaming conversation. If the conversation is the
    /// currently viewed one, uses `chatMessages`. Otherwise, uses the streaming cache.
    private func getStreamingMessages(chatId: String) -> [ChatMessage] {
        if chatId == selectedConversationID {
            return chatMessages
        }
        return streamingMessagesCache[chatId] ?? messageCache[chatId] ?? []
    }

    /// Update messages for a streaming conversation.
    private func setStreamingMessages(chatId: String, messages: [ChatMessage]) {
        if chatId == selectedConversationID {
            chatMessages = messages
        } else {
            streamingMessagesCache[chatId] = messages
        }
        // Always keep the message cache in sync
        messageCache[chatId] = messages
    }

    var isLoadingConversations: Bool = false
    var isLoadingChat: Bool = false
    var currentPage: Int = 1
    var hasMoreConversations: Bool = true
    var isLoadingMoreConversations: Bool = false

    /// Active streaming task for mini chat — cancelled when user taps stop.
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

    // MARK: - Server Tool Dialogs (ack-based)

    /// Active confirmation dialog request from a server tool (e.g. "Are you sure you want to delete?")
    var pendingConfirmation: ToolConfirmationRequest?

    /// Active input dialog request from a server tool (e.g. "Enter API key:")
    var pendingInput: ToolInputRequest?

    /// A confirmation dialog requested by a server tool via Socket.IO ack.
    struct ToolConfirmationRequest: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirmText: String
        let cancelText: String
        let ack: ([Any]) -> Void
    }

    /// A text input dialog requested by a server tool via Socket.IO ack.
    struct ToolInputRequest: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let placeholder: String
        let initialValue: String
        let confirmText: String
        let cancelText: String
        let ack: ([Any]) -> Void
    }

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

    // MARK: - Tags

    /// All tags across all conversations (fetched from server).
    var allTags: [String] = []
    /// Whether the tag editor sheet is being shown.
    var isTagEditorPresented: Bool = false
    /// The conversation ID being edited in the tag editor.
    var tagEditorConversationID: String?

    /// Parsed search components from the search text.
    /// Supports `tag:<name>` tokens for filtering by tag and plain text for title search.
    private var parsedSearch: (tags: [String], text: String) {
        var tags: [String] = []
        var textParts: [String] = []
        // Split by spaces but respect tag: tokens
        let components = searchText.components(separatedBy: " ")
        var i = 0
        while i < components.count {
            let comp = components[i]
            if comp.lowercased().hasPrefix("tag:") {
                let tagValue = String(comp.dropFirst(4)).lowercased()
                if !tagValue.isEmpty {
                    tags.append(tagValue)
                }
                // "tag:" alone (no value yet) — skip, user is still typing
            } else if !comp.isEmpty {
                textParts.append(comp)
            }
            i += 1
        }
        return (tags: tags, text: textParts.joined(separator: " "))
    }

    var filteredConversations: [ChatListItem] {
        let parsed = parsedSearch
        var result = conversations

        // Filter by tags (supports multiple tag: tokens)
        for tag in parsed.tags {
            if tag == "none" {
                // Special: "Untagged" — show conversations with no tags
                result = result.filter { $0.tagList.isEmpty }
            } else {
                result = result.filter { $0.tagList.contains(tag) }
            }
        }

        // Then filter by text search
        if !parsed.text.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(parsed.text)
            }
        }

        return result
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

    // MARK: - Temporary Chat

    /// Whether the current chat session is temporary (not persisted to server).
    /// Resets to `temporaryChatDefault` when a new conversation is started.
    var isTemporaryChat: Bool = false

    /// Whether new chats should default to temporary mode. Persisted in config.json.
    var temporaryChatDefault: Bool = false {
        didSet { guard !isLoadingConfig else { return }; saveServers() }
    }

    /// Set to true during loadServers() to prevent didSet observers from writing
    /// incomplete state back to disk before config is fully hydrated.
    private var isLoadingConfig = false

    // MARK: - Hotkey Preferences

    /// User-customizable global hotkey bindings. Persisted in config.json.
    var hotkeyPreferences: HotkeyPreferences = .defaults

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

    /// Whether persistent services (tray, hotkeys, mini chat) have been set up.
    /// These survive window close/reopen cycles and are only initialized once.
    private var hasSetupPersistentServices = false

    func onAppear() async {
        setupPersistentServicesIfNeeded()

        if let server = activeServer {
            // Already have a saved server, try to reconnect
            serverURL = server.url
            client = OpenWebUIClient(baseURL: server.url, apiKey: server.apiKey)
            let healthy = await connectionManager.checkHealth(url: server.url)
            if healthy {
                // Validate the token before proceeding
                let tokenValid = await client!.validateToken()
                if tokenValid {
                    serverReachable = true
                    serverVersion = await connectionManager.fetchVersion(url: server.url)
                    await loadModels()
                    await loadConversations()
                    await loadUser()
                    currentScreen = .chat
                    // Connect Socket.IO after navigating to chat so it doesn't
                    // block the UI. If the connection fails, chat still works via SSE.
                    socketService.connect(url: server.url, token: server.apiKey)
                } else {
                    // Token expired — try to re-authenticate
                    let reauthSuccess = await attemptReauthentication(for: server)
                    if reauthSuccess {
                        serverReachable = true
                        serverVersion = await connectionManager.fetchVersion(url: server.url)
                        await loadModels()
                        await loadConversations()
                        await loadUser()
                        currentScreen = .chat
                    } else {
                        // Re-auth failed, send to connect screen with pre-filled fields
                        prefillConnectFields(from: server)
                        connectionError = "Your session has expired. Please sign in again."
                        currentScreen = .connect
                    }
                }
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

    /// Set up persistent services that should survive window close/reopen.
    /// Only runs once — subsequent calls are no-ops.
    private func setupPersistentServicesIfNeeded() {
        guard !hasSetupPersistentServices else { return }
        hasSetupPersistentServices = true

        trayManager.setup(appState: self)
        miniChatWindowManager.setup(appState: self)
        voiceModeManager.setup(appState: self)
        voiceModeWindowManager.setup(appState: self)
        transcriptionWindowManager.setup(appState: self)
        realtimeTranscriptionManager.setDiarizationManager(speakerDiarizationManager)
        setupHotkeys()
    }

    /// Called when the main window disappears (e.g. user clicks the red close button).
    /// Intentionally does NOT tear down persistent services — they must survive window close.
    func onDisappear() {
        // No-op: tray, hotkeys, and mini chat persist for the app's lifetime.
    }

    /// Full teardown for app termination.
    func teardownAll() {
        trayManager.teardown()
        hotkeyManager.stop()
        miniChatWindowManager.teardown()
        voiceModeWindowManager.teardown()
        transcriptionWindowManager.teardown()
        hasSetupPersistentServices = false
    }

    // MARK: - Hotkey Setup

    private func setupHotkeys() {
        hotkeyManager.bindings = hotkeyPreferences
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

    /// Called when the user changes a hotkey in Settings. Persists and re-registers.
    func applyHotkeyChanges() {
        hotkeyManager.bindings = hotkeyPreferences
        hotkeyManager.restart()
        saveServers() // persist to config.json
        trayManager.updateMenu() // refresh tray shortcut labels
    }

    private func toggleMainWindow() {
        if let window = NSApp.windows.first(where: {
            !($0 is NSPanel) && $0.className != "NSMenuWindowManagerWindow"
        }) {
            if window.isVisible && window.isKeyWindow {
                window.orderOut(nil)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            // No main window exists (user closed it) — activate app so SwiftUI recreates it
            NSApp.activate(ignoringOtherApps: true)
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

        // Connect Socket.IO for real-time events (non-blocking, chat works via SSE if this fails)
        socketService.connect(url: url, token: token)

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
        // Delete Keychain tokens for all servers being disconnected
        for server in servers {
            KeychainManager.deleteToken(for: server.id)
        }
        servers = []
        activeServerID = nil
        saveServers()
        currentScreen = .connect
        trayManager.updateMenu()
    }

    // MARK: - Re-authentication

    /// Attempt to re-authenticate with the server when the saved token has expired.
    /// For email+password auth, re-signs in using the saved email (password is not saved,
    /// so this only works if the server issues long-lived tokens or uses API keys).
    /// For API key auth, the key should not expire, so validation failure means the key
    /// was revoked — re-auth is not possible.
    /// For SSO, re-auth requires user interaction — not possible automatically.
    private func attemptReauthentication(for server: ServerConfig) async -> Bool {
        // API keys don't expire in the normal sense — if validation failed,
        // the key was likely revoked. Can't re-auth automatically.
        // SSO requires interactive browser login — can't re-auth automatically.
        // Email+password: we have the email saved but NOT the password (by design).
        // We cannot silently re-authenticate without the password.
        //
        // For now, return false and let the user re-enter credentials.
        // In the future, we could store a refresh token if the server supports it.
        return false
    }

    /// Pre-fill the connect form fields from a saved server config so the user
    /// doesn't have to re-enter everything from scratch.
    private func prefillConnectFields(from server: ServerConfig) {
        urlInput = server.url
        selectedAuthMethod = server.authMethod
        if let email = server.email {
            emailInput = email
        }
        // apiKey is not pre-filled into the input for security — the user
        // should enter a new one if the old one was revoked.
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
        // Remove Keychain token for the deleted server
        KeychainManager.deleteToken(for: id)
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
            // Validate the token before loading data
            let tokenValid = await client!.validateToken()
            if tokenValid {
                // Connect Socket.IO for real-time events
                socketService.connect(url: server.url, token: server.apiKey)

                serverVersion = await connectionManager.fetchVersion(url: server.url)
                async let modelsResult: () = loadModels()
                async let chatsResult: () = loadConversations()
                async let userResult: () = loadUser()
                _ = await (modelsResult, chatsResult, userResult)
            } else {
                // Token expired for this server
                prefillConnectFields(from: server)
                connectionError = "Your session has expired. Please sign in again."
                currentScreen = .connect
            }
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
        // Cancel all active streaming tasks
        for (chatId, _) in streamingTaskByChat {
            stopStreaming(chatId: chatId)
        }
        streamingChatIDs.removeAll()
        streamingContentByChat.removeAll()
        streamingTaskByChat.removeAll()
        streamingMessageIdByChat.removeAll()
        streamingMessagesCache.removeAll()
        searchText = ""
        messageCache = [:]
        socketService.disconnect()
        ModelImageLoader.shared.clearCache()
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
        socketService.onEvent = { [weak self] chatId, messageId, eventType, data, ack in
            Task { @MainActor in
                self?.handleSocketEvent(chatId: chatId, messageId: messageId, type: eventType, data: data, ack: ack)
                // Reset watchdog on any incoming event for this streaming chat
                self?.resetWatchdog(chatId: chatId)
            }
        }

        socketService.onReconnect = { [weak self] newSessionId in
            Task { @MainActor in
                guard let self else { return }
                ovalLog.info("[Oval] Socket.IO reconnected with new sessionId: \(newSessionId)")
                // Attempt to recover missed content for any active streaming chats
                for chatId in self.streamingChatIDs {
                    self.attemptReconnectionRecovery(chatId: chatId)
                }
            }
        }
    }

    private func handleSocketEvent(chatId: String, messageId: String, type: String, data: [String: Any], ack: (([Any]) -> Void)? = nil) {
        // Resolve streaming message ID for this chat (per-conversation)
        let streamingMsgId = streamingMessageIdByChat[chatId]

        // Message ID validation: ignore events targeted at a different message
        let isValidMessage = messageId.isEmpty || streamingMsgId == nil || messageId == streamingMsgId

        switch type {

        // ── Status updates (web search progress, knowledge search, etc.) ──
        case "status", "event:status":
            guard let statusEvent = SocketService.parseStatusEvent(from: data) else { return }
            if let msgId = streamingMsgId {
                var messages = getStreamingMessages(chatId: chatId)
                if let idx = messages.lastIndex(where: { $0.id == msgId }) {
                    var msg = messages[idx]
                    var history = msg.statusHistory ?? []
                    if let lastIdx = history.lastIndex(where: { $0.action == statusEvent.action && !$0.done }) {
                        history[lastIdx] = statusEvent
                    } else {
                        history.append(statusEvent)
                    }
                    msg.statusHistory = history
                    messages[idx] = msg
                    setStreamingMessages(chatId: chatId, messages: messages)
                }
            }

        // ── Main streaming content via Socket.IO ──
        case "chat:completion":
            guard isValidMessage else { return }

            // 1. Process usage statistics
            if let usageData = data["usage"] as? [String: Any], !usageData.isEmpty {
                if let msgId = streamingMsgId {
                    var messages = getStreamingMessages(chatId: chatId)
                    if let idx = messages.lastIndex(where: { $0.id == msgId }) {
                        var msg = messages[idx]
                        msg.usage = TokenUsage(
                            prompt_tokens: usageData["prompt_tokens"] as? Int,
                            completion_tokens: usageData["completion_tokens"] as? Int,
                            total_tokens: usageData["total_tokens"] as? Int
                        )
                        messages[idx] = msg
                        setStreamingMessages(chatId: chatId, messages: messages)
                    }
                }
            }

            // 2. Process sources/citations inline
            if let rawSources = data["sources"] ?? data["citations"] {
                if let sourcesArray = rawSources as? [[String: Any]] {
                    for sourceData in sourcesArray {
                        if let sourceRef = ChatSourceReference.fromSocketPayload(sourceData) {
                            appendSource(sourceRef, toChatId: chatId, messageId: streamingMsgId)
                        }
                    }
                }
            }

            // 3. Process tool_calls (flat format)
            if let toolCallsData = data["tool_calls"] as? [[String: Any]] {
                for tcData in toolCallsData {
                    let chunk = ToolCallChunk(
                        index: tcData["index"] as? Int,
                        id: tcData["id"] as? String,
                        type: tcData["type"] as? String,
                        function: {
                            guard let fn = tcData["function"] as? [String: Any] else { return nil }
                            return ToolCallFunction(
                                name: fn["name"] as? String,
                                arguments: fn["arguments"] as? String
                            )
                        }()
                    )
                    socketStreamContinuation?.yield(.toolCall(chunk))
                }
            }

            // 4. Process choices (OpenAI-style streaming format — incremental deltas)
            var hadChoicesContent = false
            if let choices = data["choices"] as? [[String: Any]], let firstChoice = choices.first {
                if let delta = firstChoice["delta"] as? [String: Any] {
                    if let content = delta["content"] as? String, !content.isEmpty {
                        socketStreamContinuation?.yield(.content(content))
                        hadChoicesContent = true
                    }
                    if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                        for tcData in toolCalls {
                            let chunk = ToolCallChunk(
                                index: tcData["index"] as? Int,
                                id: tcData["id"] as? String,
                                type: tcData["type"] as? String,
                                function: {
                                    guard let fn = tcData["function"] as? [String: Any] else { return nil }
                                    return ToolCallFunction(
                                        name: fn["name"] as? String,
                                        arguments: fn["arguments"] as? String
                                    )
                                }()
                            )
                            socketStreamContinuation?.yield(.toolCall(chunk))
                        }
                        hadChoicesContent = true
                    }
                }
            }

            // 5. Process flat content — this is the FULL accumulated content from the server,
            //    NOT an incremental delta. Replace (don't append) the message content.
            //    Only process if choices didn't already provide content (avoid double-counting).
            if !hadChoicesContent, let content = data["content"] as? String, !content.isEmpty {
                // Replace the streaming content entirely (server sends full text so far)
                streamingContentByChat[chatId] = content
                if let msgId = streamingMsgId {
                    var messages = getStreamingMessages(chatId: chatId)
                    if let idx = messages.lastIndex(where: { $0.id == msgId }) {
                        var msg = messages[idx]
                        var updated = ChatMessage(
                            id: msg.id,
                            role: msg.role,
                            content: content,
                            model: msg.model,
                            timestamp: msg.timestamp,
                            parentId: msg.parentId,
                            childrenIds: msg.childrenIds
                        )
                        updated.toolCalls = msg.toolCalls
                        updated.statusHistory = msg.statusHistory
                        updated.sources = msg.sources
                        updated.codeExecutions = msg.codeExecutions
                        updated.followUps = msg.followUps
                        updated.usage = msg.usage
                        updated.messageError = msg.messageError
                        messages[idx] = updated
                        setStreamingMessages(chatId: chatId, messages: messages)
                    }
                }
            }

            // 6. Check done LAST (after processing all data in this event)
            if let done = data["done"] as? Bool, done {
                socketStreamContinuation?.yield(.done)
                socketStreamContinuation?.finish()
                socketStreamContinuation = nil
            }

        // ── Incremental content append ──
        case "message", "chat:message:delta", "event:message:delta":
            guard isValidMessage else { return }
            if let content = data["content"] as? String, !content.isEmpty {
                socketStreamContinuation?.yield(.content(content))
            }

        // ── Full content replacement ──
        case "replace", "chat:message":
            guard isValidMessage else { return }
            if let content = data["content"] as? String {
                streamingContentByChat[chatId] = content
                if let msgId = streamingMsgId {
                    var messages = getStreamingMessages(chatId: chatId)
                    if let idx = messages.lastIndex(where: { $0.id == msgId }) {
                        var msg = messages[idx]
                        let updated = ChatMessage(
                            id: msg.id,
                            role: msg.role,
                            content: content,
                            model: msg.model,
                            timestamp: msg.timestamp,
                            parentId: msg.parentId,
                            childrenIds: msg.childrenIds
                        )
                        msg = updated
                        msg.statusHistory = messages[idx].statusHistory
                        msg.toolCalls = messages[idx].toolCalls
                        msg.toolCallId = messages[idx].toolCallId
                        msg.sources = messages[idx].sources
                        msg.usage = messages[idx].usage
                        messages[idx] = msg
                        setStreamingMessages(chatId: chatId, messages: messages)
                    }
                }
            }

        // ── Source / Citation events ──
        case "source", "citation":
            // Check if this is a code_execution sub-type
            if let sourceType = data["type"] as? String, sourceType == "code_execution" {
                if let codeExec = ChatCodeExecution.fromSocketPayload(data) {
                    if let msgId = streamingMsgId {
                        var messages = getStreamingMessages(chatId: chatId)
                        if let idx = messages.lastIndex(where: { $0.id == msgId }) {
                            var msg = messages[idx]
                            var execs = msg.codeExecutions ?? []
                            // Upsert by ID
                            if let existingIdx = execs.firstIndex(where: { $0.id == codeExec.id }) {
                                execs[existingIdx] = codeExec
                            } else {
                                execs.append(codeExec)
                            }
                            msg.codeExecutions = execs
                            messages[idx] = msg
                            setStreamingMessages(chatId: chatId, messages: messages)
                        }
                    }
                }
            } else {
                if let sourceRef = ChatSourceReference.fromSocketPayload(data) {
                    appendSource(sourceRef, toChatId: chatId, messageId: streamingMsgId)
                }
            }

        // ── Error on assistant message — stop streaming ──
        case "chat:message:error":
            var errorContent = ""
            if let err = data["error"] as? [String: Any] {
                errorContent = err["content"] as? String ?? ""
            } else if let err = data["error"] as? String {
                errorContent = err
            } else if let msg = data["message"] as? String {
                errorContent = msg
            }
            if let msgId = streamingMsgId {
                var messages = getStreamingMessages(chatId: chatId)
                if let idx = messages.lastIndex(where: { $0.id == msgId }) {
                    var msg = messages[idx]
                    msg.messageError = ChatMessageError(content: errorContent.isEmpty ? nil : errorContent)
                    // Remove incomplete knowledge_search statuses
                    msg.statusHistory = msg.statusHistory?.filter { $0.action != "knowledge_search" || $0.done }
                    messages[idx] = msg
                    setStreamingMessages(chatId: chatId, messages: messages)
                }
            }
            socketStreamContinuation?.yield(.done)
            socketStreamContinuation?.finish()
            socketStreamContinuation = nil

        // ── Cancel all tasks ──
        case "chat:tasks:cancel":
            socketStreamContinuation?.yield(.done)
            socketStreamContinuation?.finish()
            socketStreamContinuation = nil

        // ── Follow-up suggestions ──
        case "chat:message:follow_ups":
            if let followUpsRaw = data["follow_ups"] ?? data["followUps"] {
                var suggestions: [String] = []
                if let arr = followUpsRaw as? [Any] {
                    suggestions = arr.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                } else if let single = followUpsRaw as? String, !single.isEmpty {
                    suggestions = [single.trimmingCharacters(in: .whitespacesAndNewlines)]
                }
                let targetId = streamingMsgId ?? messageId
                if !targetId.isEmpty && !suggestions.isEmpty {
                    var messages = getStreamingMessages(chatId: chatId)
                    if let idx = messages.lastIndex(where: { $0.id == targetId }) {
                        var msg = messages[idx]
                        msg.followUps = suggestions
                        messages[idx] = msg
                        setStreamingMessages(chatId: chatId, messages: messages)
                    }
                }
            }

        // ── Real-time title update from server ──
        case "chat:title":
            if let title = data["title"] as? String ?? (data.isEmpty ? nil : "\(data)") as? String,
               !title.isEmpty {
                // Update the conversation title in the sidebar
                if let idx = conversations.firstIndex(where: { $0.id == chatId }) {
                    conversations[idx] = ChatListItem(
                        id: conversations[idx].id,
                        title: title,
                        updated_at: conversations[idx].updated_at,
                        created_at: conversations[idx].created_at,
                        pinned: conversations[idx].pinned,
                        folder_id: conversations[idx].folder_id,
                        tags: conversations[idx].tags
                    )
                }
            }

        // ── Server-sent notification ──
        case "notification":
            let notifType = data["type"] as? String ?? "info"
            let content = data["content"] as? String ?? ""
            if !content.isEmpty {
                let style: ToastItem.Style = notifType == "error" ? .error : (notifType == "warning" || notifType == "warn") ? .warning : .success
                toastManager.show(content, style: style)
            }

        // ── Execute tool event ──
        case "execute:tool":
            let name = data["name"] as? String ?? "tool"
            let toolBlock = "\n<details type=\"tool_calls\" done=\"false\" name=\"\(name)\"><summary>Executing...</summary>\n</details>\n"
            socketStreamContinuation?.yield(.content(toolBlock))

        // ── File/image attachments from server ──
        case "chat:message:files", "files", "event:tool":
            // Extract files from the payload and attach to the message
            if let msgId = streamingMsgId {
                var messages = getStreamingMessages(chatId: chatId)
                if let idx = messages.lastIndex(where: { $0.id == msgId }) {
                    var msg = messages[idx]
                    var currentFiles = msg.serverFiles ?? []
                    // Extract from data["files"] or data itself
                    let filesToAdd: [[String: Any]]
                    if let f = data["files"] as? [[String: Any]] {
                        filesToAdd = f
                    } else if let f = data["result"] as? [[String: Any]] {
                        filesToAdd = f
                    } else {
                        filesToAdd = []
                    }
                    currentFiles.append(contentsOf: filesToAdd)
                    msg.serverFiles = currentFiles
                    messages[idx] = msg
                    setStreamingMessages(chatId: chatId, messages: messages)
                }
            }

        // ── Confirmation dialog (ack-based) ──
        case "confirmation":
            guard let ack else { break }
            let title = data["title"] as? String ?? "Confirm"
            let message = data["message"] as? String ?? ""
            let confirmText = data["confirm_text"] as? String ?? "Confirm"
            let cancelText = data["cancel_text"] as? String ?? "Cancel"
            pendingConfirmation = ToolConfirmationRequest(
                title: title,
                message: message,
                confirmText: confirmText,
                cancelText: cancelText,
                ack: ack
            )

        // ── Text input dialog (ack-based) ──
        case "input":
            guard let ack else { break }
            let title = data["title"] as? String ?? "Input Required"
            let message = data["message"] as? String ?? ""
            let placeholder = data["placeholder"] as? String ?? ""
            let initialValue = data["value"] as? String ?? ""
            let confirmText = data["confirm_text"] as? String ?? "Submit"
            let cancelText = data["cancel_text"] as? String ?? "Cancel"
            pendingInput = ToolInputRequest(
                title: title,
                message: message,
                placeholder: placeholder,
                initialValue: initialValue,
                confirmText: confirmText,
                cancelText: cancelText,
                ack: ack
            )

        // ── Client-side execute request (not supported — return error via ack) ──
        case "execute":
            if let ack {
                let description = data["description"] as? String
                let errorMsg = (description?.isEmpty == false) ? description! : "Client-side execute events are not supported."
                ack([["error": errorMsg]])
                toastManager.show(errorMsg, style: .warning)
            }

        // ── Chat tags updated ──
        case "chat:tags":
            // Notification only — we don't currently track tags locally
            break

        default:
            break
        }
    }

    // MARK: - Socket Event Helpers

    /// Append a source reference to the streaming message in a conversation.
    private func appendSource(_ source: ChatSourceReference, toChatId chatId: String, messageId: String?) {
        guard let msgId = messageId else { return }
        var messages = getStreamingMessages(chatId: chatId)
        guard let idx = messages.lastIndex(where: { $0.id == msgId }) else { return }
        var msg = messages[idx]
        var sources = msg.sources ?? []
        // Deduplicate by ID
        if !sources.contains(where: { $0.id == source.id }) {
            sources.append(source)
        }
        msg.sources = sources
        messages[idx] = msg
        setStreamingMessages(chatId: chatId, messages: messages)
    }

    /// Mark any remaining `done == false` status entries as done.
    /// Called as a safety net when streaming finishes, so spinners don't persist
    /// if the server never sent the final `done: true` status event.
    private func finalizeIncompleteStatuses(chatId: String, messageId: String) {
        var messages = getStreamingMessages(chatId: chatId)
        guard let idx = messages.lastIndex(where: { $0.id == messageId }) else { return }
        var msg = messages[idx]
        guard var history = msg.statusHistory, !history.isEmpty else { return }
        var changed = false
        for i in history.indices where !history[i].done {
            history[i] = StatusEvent(
                action: history[i].action,
                description: history[i].description,
                done: true,
                error: history[i].error,
                queries: history[i].queries,
                urls: history[i].urls,
                items: history[i].items
            )
            changed = true
        }
        if changed {
            msg.statusHistory = history
            messages[idx] = msg
            setStreamingMessages(chatId: chatId, messages: messages)
        }
    }

    // MARK: - Models

    func loadModels() async {
        guard let client else { return }
        do {
            models = try await client.listModels()

            // Restore model selection with priority cascade:
            // 1. Previously selected model (from last session)
            // 2. User's explicit default model
            // 3. First available model (fallback)
            if selectedModel == nil {
                if let persistedID = _persistedSelectedModelID,
                   let match = models.first(where: { $0.id == persistedID }) {
                    selectedModel = match
                } else if let defaultID = _persistedDefaultModelID ?? defaultModelID,
                          let match = models.first(where: { $0.id == defaultID }) {
                    selectedModel = match
                } else if let first = models.first {
                    selectedModel = first
                }
            } else {
                // Ensure the currently selected model still exists in the model list
                if let current = selectedModel, !models.contains(where: { $0.id == current.id }) {
                    selectedModel = models.first
                }
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
            // Load tags in background
            Task { await loadAllTags() }
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
        // Saved conversations are never temporary
        isTemporaryChat = false
        // Save current conversation's messages before switching
        if let currentId = selectedConversationID {
            messageCache[currentId] = chatMessages
            // If the current conversation is streaming, also save to the streaming cache
            if streamingChatIDs.contains(currentId) {
                streamingMessagesCache[currentId] = chatMessages
            }
        }

        selectedConversationID = id

        // In demo mode, just use the cache (no server to fetch from)
        if isDemoMode {
            chatMessages = messageCache[id] ?? []
            return
        }

        // If switching to a conversation that's currently streaming, use its cached messages
        if streamingChatIDs.contains(id) {
            chatMessages = streamingMessagesCache[id] ?? messageCache[id] ?? []
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

    /// Move a conversation to the top of the sidebar (update its timestamp locally).
    private func bumpConversationToTop(chatId: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == chatId }) else { return }
        let old = conversations[idx]
        let updated = ChatListItem(
            id: old.id,
            title: old.title,
            updated_at: Date().timeIntervalSince1970,
            created_at: old.created_at,
            pinned: old.pinned,
            folder_id: old.folder_id,
            tags: old.tags
        )
        conversations.remove(at: idx)
        conversations.insert(updated, at: 0)
    }

    func newConversation() {
        selectedConversationID = nil
        chatMessages = []
        messageInput = ""
        pendingAttachments = []
        isTemporaryChat = temporaryChatDefault
    }

    /// Start a new temporary chat session regardless of the default setting.
    func newTemporaryConversation() {
        newConversation()
        isTemporaryChat = true
    }

    /// Start a new conversation with a specific model pre-selected.
    func newConversationWithModel(_ model: AIModel) {
        selectedModel = model
        newConversation()
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
                let old = conversations[idx]
                conversations[idx] = ChatListItem(
                    id: id,
                    title: title,
                    updated_at: old.updated_at,
                    created_at: old.created_at,
                    pinned: old.pinned,
                    folder_id: old.folder_id,
                    tags: old.tags
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

    // MARK: - Chat Context Menu Actions

    /// Share a chat — creates a shareable link. Copies the share URL to clipboard.
    func shareConversation(_ id: String) async {
        guard let client else { return }
        do {
            let response = try await client.shareChat(id: id)
            if let shareId = response.share_id {
                let shareURL = "\(client.baseURL)/s/\(shareId)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shareURL, forType: .string)
                toastManager.show("Share link copied to clipboard", style: .success)
            }
        } catch {
            toastManager.show("Failed to share: \(error.localizedDescription)", style: .error)
        }
    }

    /// Clone (duplicate) a chat.
    func cloneConversation(_ id: String) async {
        guard let client else { return }
        do {
            let cloned = try await client.cloneChat(id: id)
            await loadConversations(silent: true)
            // Navigate to the cloned chat
            suppressConversationSelection = true
            selectedConversationID = cloned.id
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                suppressConversationSelection = false
            }
            await loadChatMessages(cloned.id)
            toastManager.show("Chat cloned", style: .success)
        } catch {
            toastManager.show("Failed to clone: \(error.localizedDescription)", style: .error)
        }
    }

    /// Toggle pin status for a chat.
    func togglePinConversation(_ id: String) async {
        guard let client else { return }
        do {
            let response = try await client.toggleChatPinned(id: id)
            let isPinned = response.pinned ?? false
            // Update local state
            if let idx = conversations.firstIndex(where: { $0.id == id }) {
                conversations[idx].pinned = isPinned
            }
            toastManager.show(isPinned ? "Chat pinned" : "Chat unpinned", style: .success)
        } catch {
            toastManager.show("Failed to toggle pin: \(error.localizedDescription)", style: .error)
        }
    }

    /// Toggle archive status for a chat. Archived chats are removed from the sidebar.
    func archiveConversation(_ id: String) async {
        guard let client else { return }
        do {
            _ = try await client.toggleChatArchived(id: id)
            // Remove from sidebar (archived chats don't show in main list)
            conversations.removeAll { $0.id == id }
            if selectedConversationID == id {
                selectedConversationID = nil
                chatMessages = []
            }
            messageCache.removeValue(forKey: id)
            toastManager.show("Chat archived", style: .success)
        } catch {
            toastManager.show("Failed to archive: \(error.localizedDescription)", style: .error)
        }
    }

    /// Download/export a chat as JSON. Opens a save panel.
    func downloadConversation(_ id: String) async {
        guard let client else { return }
        do {
            let chat = try await client.getChat(id: id)
            let data = try JSONEncoder().encode([chat])

            let panel = NSSavePanel()
            panel.nameFieldStringValue = "chat-export-\(id).json"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true

            let result = await panel.begin()
            if result == .OK, let url = panel.url {
                try data.write(to: url)
                toastManager.show("Chat exported", style: .success)
            }
        } catch {
            toastManager.show("Failed to export: \(error.localizedDescription)", style: .error)
        }
    }

    /// Move a chat to a folder.
    func moveConversation(_ id: String, toFolder folderId: String?) async {
        guard let client else { return }
        do {
            _ = try await client.moveChatToFolder(id: id, folderId: folderId)
            await loadConversations(silent: true)
            toastManager.show("Chat moved", style: .success)
        } catch {
            toastManager.show("Failed to move: \(error.localizedDescription)", style: .error)
        }
    }

    /// Load available folders for the Move submenu.
    func loadFolders() async -> [ChatFolder] {
        guard let client else { return [] }
        do {
            return try await client.listFolders()
        } catch {
            return []
        }
    }

    // MARK: - Temporary Chat

    /// Save the current temporary chat to the server, making it permanent.
    func saveTemporaryChat() async {
        guard isTemporaryChat, let client else { return }
        guard !chatMessages.isEmpty else { return }

        let title = chatMessages.first(where: { $0.role == "user" })
            .map { String($0.content.prefix(100)) } ?? "Saved Chat"
        let blob = buildChatBlob(title: title, assistantId: nil, assistantModel: nil)

        do {
            let created = try await client.createChatWithHistory(blob: blob)
            isTemporaryChat = false
            suppressConversationSelection = true
            selectedConversationID = created.id
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                suppressConversationSelection = false
            }
            await loadConversations(silent: true)
            toastManager.show(String(localized: "tempChat.savedToast"), style: .success)
        } catch {
            toastManager.show("Failed to save chat: \(error.localizedDescription)", style: .error)
        }
    }

    // MARK: - Tag Management

    /// Fetch all tags from the server and update the local list.
    func loadAllTags() async {
        guard let client else { return }
        do {
            allTags = try await client.getAllTags()
        } catch {
            // Silently fail — tags are non-critical
        }
    }

    /// Add a tag to a conversation. Updates local state and server.
    func addTag(to conversationId: String, tagName: String) async {
        let tag = tagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !tag.isEmpty, let client else { return }
        do {
            try await client.addTagToChat(id: conversationId, tagName: tag)
            // Update local conversation tags
            if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
                var tags = conversations[idx].tags ?? []
                if !tags.contains(tag) {
                    tags.append(tag)
                    conversations[idx].tags = tags
                }
            }
            // Add to global tags list if new
            if !allTags.contains(tag) {
                allTags.append(tag)
            }
        } catch {
            toastManager.show("Failed to add tag: \(error.localizedDescription)", style: .error)
        }
    }

    /// Remove a tag from a conversation. Updates local state and server.
    func removeTag(from conversationId: String, tagName: String) async {
        guard let client else { return }
        do {
            try await client.removeTagFromChat(id: conversationId, tagName: tagName)
            // Update local conversation tags
            if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
                conversations[idx].tags?.removeAll { $0 == tagName }
            }
            // Refresh global tags (a tag might no longer exist on any conversation)
            await loadAllTags()
        } catch {
            toastManager.show("Failed to remove tag: \(error.localizedDescription)", style: .error)
        }
    }

    /// Open the tag editor for a specific conversation.
    func showTagEditor(for conversationId: String) {
        tagEditorConversationID = conversationId
        isTagEditorPresented = true
    }

    /// Clear the tag filter by removing all `tag:` tokens from the search text.
    func clearTagFilter() {
        searchText = searchText.components(separatedBy: " ")
            .filter { !$0.lowercased().hasPrefix("tag:") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
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
            ovalLog.error("[Oval] sendMessage: GUARD FAIL — selectedModel=\(self.selectedModel?.id ?? "nil") client=\(self.client != nil ? "yes" : "nil")")
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

        // ── Step 1: Create chat on server if this is a new conversation (skipped for temp chats) ──
        if isNewConversation {
            if isTemporaryChat {
                // Temporary chat: assign a local ID without creating a server record
                suppressConversationSelection = true
                selectedConversationID = "local:\(UUID().uuidString)"
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    suppressConversationSelection = false
                }
            } else {
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
        }

        // Capture the chat ID now — this won't change even if the user switches conversations
        guard let chatId = selectedConversationID else { return }

        // For existing non-temp conversations, update updated_at and refresh sidebar.
        if !isNewConversation && !isTemporaryChat {
            let earlyBlob = buildChatBlob(title: conversations.first(where: { $0.id == chatId })?.title ?? "Chat", assistantId: nil, assistantModel: nil)
            Task {
                _ = try? await client.updateChat(id: chatId, blob: earlyBlob)
                await self.loadConversations(silent: true)
            }
        } else if !isTemporaryChat {
            // New non-temp conversation — refresh sidebar to pick it up
            Task { await self.loadConversations(silent: true) }
        }

        // Build completion messages (multimodal for the current message if it has images)
        let completionMsgs = Self.buildCompletionMessages(from: chatMessages)

        // ── Step 2: Start streaming ──
        beginStreaming(chatId: chatId)

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
        // Sync initial messages to the cache so background streaming can find them
        messageCache[chatId] = chatMessages

        // Track the message ID for Socket.IO event routing (per-conversation)
        streamingMessageIdByChat[chatId] = assistantId

        // Move this conversation to the top of the sidebar immediately
        bumpConversationToTop(chatId: chatId)

        let webSearchEnabled = isWebSearchEnabled

        // Capture Socket.IO session ID so the server routes events through the socket
        // instead of SSE. This is critical for native tool calling — the server sends
        // tool execution status and the follow-up model response via Socket.IO events.
        let socketSessionId = socketService.isConnected ? socketService.sessionId : nil
        // Capture at send time to avoid race with saveTemporaryChat() during streaming
        let isTempChat = isTemporaryChat

        // Wrap streaming in a cancellable task — runs in background even if user switches chats
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let fileRefs = uploadedFileRefs.isEmpty ? nil : uploadedFileRefs

                // When Socket.IO is connected, pass sessionId and chatId so the server
                // streams via Socket.IO events. This enables multi-phase tool call flows
                // where the server executes tools and re-invokes the model.
                let continuationRef = socketSessionId != nil ? SocketStreamContinuationRef() : nil
                let stream = await client.streamChat(
                    model: model.id,
                    messages: completionMsgs,
                    files: fileRefs,
                    webSearch: webSearchEnabled,
                    sessionId: socketSessionId,
                    chatId: socketSessionId != nil ? chatId : nil,
                    messageId: assistantId,
                    parentId: userMsg.id,
                    socketContinuationRef: continuationRef
                )
                // Wire the Socket.IO continuation after streamChat populates it
                if let ref = continuationRef {
                    self.socketStreamContinuation = ref.continuation
                }
                var toolCallAccumulator: [Int: (id: String, type: String, name: String, arguments: String)] = [:]

                for try await delta in stream {
                    if Task.isCancelled { break }
                    switch delta {
                    case .content(let text):
                        self.streamingContentByChat[chatId, default: ""] += text
                    case .toolCall(let tc):
                        let idx = tc.index ?? 0
                        var entry = toolCallAccumulator[idx] ?? (id: "", type: "function", name: "", arguments: "")
                        if let id = tc.id { entry.id = id }
                        if let type = tc.type { entry.type = type }
                        if let name = tc.function?.name { entry.name += name }
                        if let args = tc.function?.arguments { entry.arguments += args }
                        toolCallAccumulator[idx] = entry
                    case .done:
                        // Reset accumulator between phases (tool call → final response)
                        toolCallAccumulator.removeAll()
                    }

                    let currentContent = self.streamingContentByChat[chatId] ?? ""

                    // Build tool calls from streaming chunks
                    var completedToolCalls: [ToolCall] = toolCallAccumulator.sorted(by: { $0.key < $1.key }).compactMap { (_, entry) in
                        guard !entry.id.isEmpty, !entry.name.isEmpty else { return nil }
                        return ToolCall(id: entry.id, type: entry.type, function: ToolCall.ToolCallComplete(name: entry.name, arguments: entry.arguments), status: .executing)
                    }

                    let parsedFromContent = Self.parseToolCallDetails(from: currentContent)
                    if !parsedFromContent.isEmpty {
                        let streamIds = Set(completedToolCalls.map(\.id))
                        for parsed in parsedFromContent {
                            if let idx = completedToolCalls.firstIndex(where: { $0.id == parsed.id }) {
                                completedToolCalls[idx] = parsed
                            } else if !streamIds.contains(parsed.id) {
                                completedToolCalls.append(parsed)
                            }
                        }
                    }

                    // Update the assistant message — use per-conversation message access
                    var messages = self.getStreamingMessages(chatId: chatId)
                    if let idx = messages.lastIndex(where: { $0.id == assistantId }) {
                        var updated = ChatMessage(
                            id: assistantId,
                            role: "assistant",
                            content: currentContent,
                            model: model.id,
                            timestamp: Date().timeIntervalSince1970,
                            parentId: userMsg.id,
                            childrenIds: nil
                        )
                        if !completedToolCalls.isEmpty {
                            updated.toolCalls = completedToolCalls
                        }
                        updated.statusHistory = messages[idx].statusHistory
                        updated.sources = messages[idx].sources
                        updated.codeExecutions = messages[idx].codeExecutions
                        updated.followUps = messages[idx].followUps
                        updated.usage = messages[idx].usage
                        updated.messageError = messages[idx].messageError
                        messages[idx] = updated
                        self.setStreamingMessages(chatId: chatId, messages: messages)
                    }
                }

                // After streaming ends, mark remaining tool calls as completed
                var messages = self.getStreamingMessages(chatId: chatId)
                if let idx = messages.lastIndex(where: { $0.id == assistantId }) {
                    var finalMsg = messages[idx]
                    if var toolCalls = finalMsg.toolCalls {
                        for i in toolCalls.indices {
                            if toolCalls[i].status == .executing || toolCalls[i].status == .pending {
                                toolCalls[i].status = .completed
                            }
                        }
                        finalMsg.toolCalls = toolCalls
                        messages[idx] = finalMsg
                        self.setStreamingMessages(chatId: chatId, messages: messages)
                    }
                }

                // Mark any incomplete status entries as done (safety net)
                self.finalizeIncompleteStatuses(chatId: chatId, messageId: assistantId)
            } catch {
                if !Task.isCancelled {
                    self.toastManager.show("Stream error: \(error.localizedDescription)", style: .error)
                }
            }

            // ── Cleanup streaming state ──
            self.endStreaming(chatId: chatId)
            self.socketStreamContinuation = nil

            if !isTempChat {
                // ── Notify server that streaming completed (triggers filters, follow-ups, etc.) ──
                let completedMessages = self.getStreamingMessages(chatId: chatId)
                let simplifiedMsgs = completedMessages.suffix(2).map {
                    ["role": $0.role, "content": $0.content, "id": $0.id]
                }
                await client.sendChatCompleted(
                    chatId: chatId,
                    messageId: assistantId,
                    messages: simplifiedMsgs,
                    model: model.id,
                    sessionId: socketSessionId ?? UUID().uuidString
                )

                // ── Save final state to server ──
                let finalMessages = self.getStreamingMessages(chatId: chatId)
                self.messageCache[chatId] = finalMessages

                let fallbackTitle = finalMessages.first(where: { $0.role == "user" })
                    .map { String($0.content.prefix(100)) } ?? "New Chat"
                let blob = self.buildChatBlob(title: fallbackTitle, assistantId: nil, assistantModel: nil)
                _ = try? await client.updateChat(id: chatId, blob: blob)

                // Generate title for new conversations
                if isNewConversation {
                    await self.generateAndSetTitle(chatId: chatId, modelId: model.id)
                }

                // Refresh sidebar from server so sort order reflects updated_at
                await self.loadConversations(silent: true)
            } else {
                // Temp chat: just cache messages locally, no server calls
                let finalMessages = self.getStreamingMessages(chatId: chatId)
                self.messageCache[chatId] = finalMessages
            }
        }
        streamingTaskByChat[chatId] = task
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
                statusHistory: msg.statusHistory?.map { StatusEventCodable(from: $0) },
                sources: msg.sources,
                codeExecutions: msg.codeExecutions,
                followUps: msg.followUps,
                usage: msg.usage,
                messageError: msg.messageError,
                done: msg.role == "assistant" ? true : nil,
                modelIdx: msg.role == "assistant" ? 0 : nil
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
                statusHistory: nil,
                sources: nil,
                codeExecutions: nil,
                followUps: nil,
                usage: nil,
                messageError: nil,
                done: false,
                modelIdx: 0
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
                    statusHistory: entry.statusHistory,
                    sources: entry.sources,
                    codeExecutions: entry.codeExecutions,
                    followUps: entry.followUps,
                    usage: entry.usage,
                    messageError: entry.messageError,
                    done: entry.done,
                    modelIdx: entry.modelIdx
                )
                historyDict[lastMsg.id] = updated
            }
        }

        let currentId = flatMessages.last?.id
        let history = ChatBlobHistory(messages: historyDict, currentId: currentId)

        // Collect unique model IDs from assistant messages
        let modelIds = Array(Set(chatMessages.compactMap { $0.role == "assistant" ? $0.model : nil }))

        return ChatBlob(title: title, history: history, messages: flatMessages,
                        models: modelIds.isEmpty ? nil : modelIds)
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
            guard let chatId = selectedConversationID else { return }

            let assistantId = UUID().uuidString
            beginStreaming(chatId: chatId)

            let parentMsgId = chatMessages[idx].id
            let assistantMsg = ChatMessage(
                id: assistantId,
                role: "assistant",
                content: "",
                model: model.id,
                timestamp: Date().timeIntervalSince1970,
                parentId: parentMsgId,
                childrenIds: nil
            )
            chatMessages.append(assistantMsg)
            messageCache[chatId] = chatMessages
            streamingMessageIdByChat[chatId] = assistantId
            bumpConversationToTop(chatId: chatId)

            let completionMsgs = Self.buildCompletionMessages(from: chatMessages)
            let webSearchEnabled = isWebSearchEnabled
            let editSocketSessionId = socketService.isConnected ? socketService.sessionId : nil
            // Capture at send time to avoid race with saveTemporaryChat() during streaming
            let isTempChat = isTemporaryChat

            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let editContinuationRef = editSocketSessionId != nil ? SocketStreamContinuationRef() : nil
                    let stream = await client.streamChat(
                        model: model.id,
                        messages: completionMsgs,
                        files: nil,
                        webSearch: webSearchEnabled,
                        sessionId: editSocketSessionId,
                        chatId: editSocketSessionId != nil ? chatId : nil,
                        messageId: assistantId,
                        parentId: parentMsgId,
                        socketContinuationRef: editContinuationRef
                    )
                    if let ref = editContinuationRef {
                        self.socketStreamContinuation = ref.continuation
                    }
                    var toolCallAccumulator: [Int: (id: String, type: String, name: String, arguments: String)] = [:]

                    for try await delta in stream {
                        if Task.isCancelled { break }
                        switch delta {
                        case .content(let text):
                            self.streamingContentByChat[chatId, default: ""] += text
                        case .toolCall(let tc):
                            let tcIdx = tc.index ?? 0
                            var entry = toolCallAccumulator[tcIdx] ?? (id: "", type: "function", name: "", arguments: "")
                            if let id = tc.id { entry.id = id }
                            if let type = tc.type { entry.type = type }
                            if let name = tc.function?.name { entry.name += name }
                            if let args = tc.function?.arguments { entry.arguments += args }
                            toolCallAccumulator[tcIdx] = entry
                        case .done:
                            // Reset accumulator between phases (tool call → final response)
                            toolCallAccumulator.removeAll()
                        }

                        let currentContent = self.streamingContentByChat[chatId] ?? ""
                        var completedToolCalls: [ToolCall] = toolCallAccumulator.sorted(by: { $0.key < $1.key }).compactMap { (_, entry) in
                            guard !entry.id.isEmpty, !entry.name.isEmpty else { return nil }
                            return ToolCall(id: entry.id, type: entry.type, function: ToolCall.ToolCallComplete(name: entry.name, arguments: entry.arguments), status: .executing)
                        }
                        let parsedFromContent = Self.parseToolCallDetails(from: currentContent)
                        for parsed in parsedFromContent {
                            if let i = completedToolCalls.firstIndex(where: { $0.id == parsed.id }) {
                                completedToolCalls[i] = parsed
                            } else if !completedToolCalls.contains(where: { $0.id == parsed.id }) {
                                completedToolCalls.append(parsed)
                            }
                        }

                        var messages = self.getStreamingMessages(chatId: chatId)
                        if let mIdx = messages.lastIndex(where: { $0.id == assistantId }) {
                            var updated = ChatMessage(
                                id: assistantId,
                                role: "assistant",
                                content: currentContent,
                                model: model.id,
                                timestamp: Date().timeIntervalSince1970,
                                parentId: parentMsgId,
                                childrenIds: nil
                            )
                            if !completedToolCalls.isEmpty { updated.toolCalls = completedToolCalls }
                            updated.statusHistory = messages[mIdx].statusHistory
                            updated.sources = messages[mIdx].sources
                            updated.codeExecutions = messages[mIdx].codeExecutions
                            updated.followUps = messages[mIdx].followUps
                            updated.usage = messages[mIdx].usage
                            updated.messageError = messages[mIdx].messageError
                            messages[mIdx] = updated
                            self.setStreamingMessages(chatId: chatId, messages: messages)
                        }
                    }

                    var messages = self.getStreamingMessages(chatId: chatId)
                    if let mIdx = messages.lastIndex(where: { $0.id == assistantId }) {
                        var finalMsg = messages[mIdx]
                        if var toolCalls = finalMsg.toolCalls {
                            for i in toolCalls.indices where toolCalls[i].status == .executing || toolCalls[i].status == .pending {
                                toolCalls[i].status = .completed
                            }
                            finalMsg.toolCalls = toolCalls
                            messages[mIdx] = finalMsg
                            self.setStreamingMessages(chatId: chatId, messages: messages)
                        }
                    }

                    // Mark any incomplete status entries as done (safety net)
                    self.finalizeIncompleteStatuses(chatId: chatId, messageId: assistantId)
                } catch {
                    if !Task.isCancelled {
                        self.toastManager.show("Stream error: \(error.localizedDescription)", style: .error)
                    }
                }

                self.endStreaming(chatId: chatId)
                self.socketStreamContinuation = nil

                if !isTempChat {
                    // Notify server that streaming completed (triggers filters, follow-ups, etc.)
                    let completedMessages = self.getStreamingMessages(chatId: chatId)
                    let simplifiedMsgs = completedMessages.suffix(2).map {
                        ["role": $0.role, "content": $0.content, "id": $0.id]
                    }
                    await client.sendChatCompleted(
                        chatId: chatId,
                        messageId: assistantId,
                        messages: simplifiedMsgs,
                        model: model.id,
                        sessionId: editSocketSessionId ?? UUID().uuidString
                    )

                    // Save to server and refresh sidebar
                    let finalMessages = self.messageCache[chatId] ?? []
                    let fallbackTitle = finalMessages.first(where: { $0.role == "user" })
                        .map { String($0.content.prefix(100)) } ?? "New Chat"
                    let blob = self.buildChatBlob(title: fallbackTitle, assistantId: nil, assistantModel: nil)
                    _ = try? await client.updateChat(id: chatId, blob: blob)
                    await self.loadConversations(silent: true)
                } else {
                    // Temp chat — cache messages locally only, skip all server persistence
                    let finalMessages = self.getStreamingMessages(chatId: chatId)
                    self.messageCache[chatId] = finalMessages
                }
            }
            streamingTaskByChat[chatId] = task
        } else {
            // Just save the edit without re-streaming
            if let convId = selectedConversationID {
                messageCache[convId] = chatMessages
                if let client, !isTemporaryChat {
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
        guard let chatId = selectedConversationID else { return }

        // Remove the assistant message and any messages after it
        chatMessages = Array(chatMessages.prefix(idx))

        guard let model = selectedModel, let client else { return }

        let assistantId = UUID().uuidString
        let parentMsgId = chatMessages.last?.id
        beginStreaming(chatId: chatId)

        let assistantMsg = ChatMessage(
            id: assistantId,
            role: "assistant",
            content: "",
            model: model.id,
            timestamp: Date().timeIntervalSince1970,
            parentId: parentMsgId,
            childrenIds: nil
        )
        chatMessages.append(assistantMsg)
        messageCache[chatId] = chatMessages
        streamingMessageIdByChat[chatId] = assistantId
        bumpConversationToTop(chatId: chatId)

        let completionMsgs = Self.buildCompletionMessages(from: Array(chatMessages.dropLast()))
        let webSearchEnabled = isWebSearchEnabled
        let regenSocketSessionId = socketService.isConnected ? socketService.sessionId : nil
        // Capture at send time to avoid race with saveTemporaryChat() during streaming
        let isTempChat = isTemporaryChat

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let regenContinuationRef = regenSocketSessionId != nil ? SocketStreamContinuationRef() : nil
                let stream = await client.streamChat(
                    model: model.id,
                    messages: completionMsgs,
                    files: nil,
                    webSearch: webSearchEnabled,
                    sessionId: regenSocketSessionId,
                    chatId: regenSocketSessionId != nil ? chatId : nil,
                    messageId: assistantId,
                    parentId: parentMsgId,
                    socketContinuationRef: regenContinuationRef
                )
                if let ref = regenContinuationRef {
                    self.socketStreamContinuation = ref.continuation
                }
                var toolCallAccumulator: [Int: (id: String, type: String, name: String, arguments: String)] = [:]

                for try await delta in stream {
                    if Task.isCancelled { break }
                    switch delta {
                    case .content(let text):
                        self.streamingContentByChat[chatId, default: ""] += text
                    case .toolCall(let tc):
                        let tcIdx = tc.index ?? 0
                        var entry = toolCallAccumulator[tcIdx] ?? (id: "", type: "function", name: "", arguments: "")
                        if let id = tc.id { entry.id = id }
                        if let type = tc.type { entry.type = type }
                        if let name = tc.function?.name { entry.name += name }
                        if let args = tc.function?.arguments { entry.arguments += args }
                        toolCallAccumulator[tcIdx] = entry
                    case .done:
                        // Reset accumulator between phases (tool call → final response)
                        toolCallAccumulator.removeAll()
                    }

                    let currentContent = self.streamingContentByChat[chatId] ?? ""
                    var completedToolCalls: [ToolCall] = toolCallAccumulator.sorted(by: { $0.key < $1.key }).compactMap { (_, entry) in
                        guard !entry.id.isEmpty, !entry.name.isEmpty else { return nil }
                        return ToolCall(id: entry.id, type: entry.type, function: ToolCall.ToolCallComplete(name: entry.name, arguments: entry.arguments), status: .executing)
                    }
                    let parsedFromContent = Self.parseToolCallDetails(from: currentContent)
                    for parsed in parsedFromContent {
                        if let i = completedToolCalls.firstIndex(where: { $0.id == parsed.id }) {
                            completedToolCalls[i] = parsed
                        } else if !completedToolCalls.contains(where: { $0.id == parsed.id }) {
                            completedToolCalls.append(parsed)
                        }
                    }

                    var messages = self.getStreamingMessages(chatId: chatId)
                    if let mIdx = messages.lastIndex(where: { $0.id == assistantId }) {
                        var updated = ChatMessage(
                            id: assistantId,
                            role: "assistant",
                            content: currentContent,
                            model: model.id,
                            timestamp: Date().timeIntervalSince1970,
                            parentId: parentMsgId,
                            childrenIds: nil
                        )
                        if !completedToolCalls.isEmpty { updated.toolCalls = completedToolCalls }
                        updated.statusHistory = messages[mIdx].statusHistory
                        updated.sources = messages[mIdx].sources
                        updated.codeExecutions = messages[mIdx].codeExecutions
                        updated.followUps = messages[mIdx].followUps
                        updated.usage = messages[mIdx].usage
                        updated.messageError = messages[mIdx].messageError
                        messages[mIdx] = updated
                        self.setStreamingMessages(chatId: chatId, messages: messages)
                    }
                }

                var messages = self.getStreamingMessages(chatId: chatId)
                if let mIdx = messages.lastIndex(where: { $0.id == assistantId }) {
                    var finalMsg = messages[mIdx]
                    if var toolCalls = finalMsg.toolCalls {
                        for i in toolCalls.indices where toolCalls[i].status == .executing || toolCalls[i].status == .pending {
                            toolCalls[i].status = .completed
                        }
                        finalMsg.toolCalls = toolCalls
                        messages[mIdx] = finalMsg
                        self.setStreamingMessages(chatId: chatId, messages: messages)
                    }
                }

                // Mark any incomplete status entries as done (safety net)
                self.finalizeIncompleteStatuses(chatId: chatId, messageId: assistantId)
            } catch {
                if !Task.isCancelled {
                    self.toastManager.show("Stream error: \(error.localizedDescription)", style: .error)
                }
            }

            self.endStreaming(chatId: chatId)
            self.socketStreamContinuation = nil

            if !isTempChat {
                // Notify server that streaming completed (triggers filters, follow-ups, etc.)
                let completedMessages = self.getStreamingMessages(chatId: chatId)
                let simplifiedMsgs = completedMessages.suffix(2).map {
                    ["role": $0.role, "content": $0.content, "id": $0.id]
                }
                await client.sendChatCompleted(
                    chatId: chatId,
                    messageId: assistantId,
                    messages: simplifiedMsgs,
                    model: model.id,
                    sessionId: regenSocketSessionId ?? UUID().uuidString
                )

                let finalMessages = self.messageCache[chatId] ?? []
                let fallbackTitle = finalMessages.first(where: { $0.role == "user" })
                    .map { String($0.content.prefix(100)) } ?? "New Chat"
                let blob = self.buildChatBlob(title: fallbackTitle, assistantId: nil, assistantModel: nil)
                _ = try? await client.updateChat(id: chatId, blob: blob)
                await self.loadConversations(silent: true)
            } else {
                // Temp chat — cache messages locally only, skip all server persistence
                let finalMessages = self.getStreamingMessages(chatId: chatId)
                self.messageCache[chatId] = finalMessages
            }
        }
        streamingTaskByChat[chatId] = task
    }

    // MARK: - Text-to-Speech

    /// Speak assistant message content.
    /// Uses RunAnywhere on-device TTS if loaded, otherwise falls back to macOS native TTS.
    /// Strips reasoning/thinking blocks before speaking.
    func speakMessage(_ content: String) {
        let cleaned = stripReasoningBlocks(content)
        ttsManager.speak(cleaned)
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

        guard let chatId = selectedConversationID else { return }

        // Pick a response based on keywords
        let lowerText = text.lowercased()
        let response = Self.demoResponses.first(where: { pair in
            pair.keywords.contains(where: { lowerText.contains($0) })
        })?.response ?? Self.defaultDemoResponse

        // Simulate streaming
        let assistantId = UUID().uuidString
        beginStreaming(chatId: chatId)

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
            guard streamingChatIDs.contains(chatId) else { break }

            streamingContentByChat[chatId, default: ""] += String(char)
            let currentContent = streamingContentByChat[chatId] ?? ""

            if let idx = chatMessages.lastIndex(where: { $0.id == assistantId }) {
                chatMessages[idx] = ChatMessage(
                    id: assistantId,
                    role: "assistant",
                    content: currentContent,
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

        endStreaming(chatId: chatId)
        messageCache[chatId] = chatMessages
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
        isLoadingConfig = true
        defer { isLoadingConfig = false }
        activeServerID = config.activeServerID
        pinnedModelIDs = config.pinnedModelIDs
        // selectedModelID and defaultModelID are restored in loadModels()
        _persistedSelectedModelID = config.selectedModelID
        _persistedDefaultModelID = config.defaultModelID
        // Restore hotkey preferences (fall back to defaults for existing configs)
        hotkeyPreferences = config.hotkeyPreferences ?? .defaults
        // Restore privacy preferences
        temporaryChatDefault = config.temporaryChatDefault
    }

    private func saveServers() {
        let config = ConfigManager.Config(
            servers: servers,
            activeServerID: activeServerID,
            selectedModelID: selectedModel?.id,
            defaultModelID: defaultModelID,
            pinnedModelIDs: pinnedModelIDs,
            hotkeyPreferences: hotkeyPreferences,
            temporaryChatDefault: temporaryChatDefault
        )
        configManager.save(config)
    }

    /// Save just the model preferences without touching server data.
    /// Called when the user changes model selection, default, or pins.
    func saveModelPreferences() {
        saveServers()
    }
}
