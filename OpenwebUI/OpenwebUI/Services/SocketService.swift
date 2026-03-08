import Combine
import Foundation
import os.log
import SocketIO

private let socketLog = Logger(subsystem: "com.oval.app", category: "socket")

/// Manages the Socket.IO connection to the Open WebUI server.
/// Receives real-time events (status updates, streaming content, sources)
/// that aren't available through the REST SSE endpoint.
@MainActor
final class SocketService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isConnected = false
    @Published private(set) var sessionId: String?

    // MARK: - Event Callbacks

    /// Called when a chat event is received (from "events" or "chat-events" channels).
    /// Parameters: (chatId, messageId, eventType, eventData, ackCallback)
    /// The ack callback can be used to send acknowledgements back to the server (e.g. for tool confirmation dialogs).
    var onEvent: ((_ chatId: String, _ messageId: String, _ type: String, _ data: [String: Any], _ ack: (([Any]) -> Void)?) -> Void)?

    /// Called when a channel event is received (from "events:channel" or "channel-events").
    /// Parameters: (channelId, messageId, eventType, eventData, ackCallback)
    var onChannelEvent: ((_ channelId: String, _ messageId: String, _ type: String, _ data: [String: Any], _ ack: (([Any]) -> Void)?) -> Void)?

    /// Called when the socket reconnects with a new session ID.
    /// Active streaming contexts should update their session reference.
    var onReconnect: ((_ newSessionId: String) -> Void)?

    // MARK: - Private

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var serverURL: String?
    private var token: String?
    private var heartbeatTimer: Timer?
    private var hasTriedPollingFallback = false

    // MARK: - Connect

    /// Connect to the Open WebUI Socket.IO server.
    /// - Parameters:
    ///   - url: The server base URL (e.g. "http://localhost:8080")
    ///   - token: The JWT auth token
    func connect(url: String, token: String) {
        // Disconnect existing connection if server/token changed
        if url == serverURL && token == self.token && isConnected {
            return
        }
        disconnect()

        self.serverURL = url
        self.token = token

        guard let serverURL = URL(string: url) else { return }

        manager = SocketManager(
            socketURL: serverURL,
            config: [
                .log(false),
                .path("/ws/socket.io"),
                .connectParams(["EIO": "4"]),
                .forceWebsockets(true),
                .reconnects(true),
                .reconnectWait(1),
                .reconnectWaitMax(5)
            ]
        )

        socket = manager?.defaultSocket

        setupEventHandlers(token: token)
        socket?.connect(withPayload: ["token": token])
    }

    // MARK: - Disconnect

    func disconnect() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        socket?.disconnect()
        socket?.removeAllHandlers()
        socket = nil
        manager?.disconnect()
        manager = nil
        isConnected = false
        sessionId = nil
    }

    // MARK: - Event Handlers

    private func setupEventHandlers(token: String) {
        guard let socket else { return }

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = true
                self.sessionId = socket.sid
                self.hasTriedPollingFallback = false

                // Send user-join to authenticate and join rooms
                socket.emit("user-join", ["auth": ["token": token]])

                // Start heartbeat (every 30s like the web frontend)
                self.startHeartbeat()
            }
        }

        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            Task { @MainActor in
                self?.isConnected = false
                self?.sessionId = nil
                self?.heartbeatTimer?.invalidate()
            }
        }

        socket.on(clientEvent: .reconnect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = true
                self.sessionId = socket.sid
                socket.emit("user-join", ["auth": ["token": token]])
                self.startHeartbeat()
                // Notify listeners of new session ID (for active streaming contexts)
                if let sid = socket.sid { self.onReconnect?(sid) }
            }
        }

        // Connection error — try falling back from WebSocket to polling
        socket.on(clientEvent: .error) { [weak self] data, _ in
            Task { @MainActor in
                guard let self, !self.hasTriedPollingFallback else { return }
                self.hasTriedPollingFallback = true
                // Reconfigure manager to allow polling fallback
                self.manager?.config.insert(.forceWebsockets(false))
                socketLog.warning("[Oval] Socket.IO connection error, retrying with polling fallback")
            }
        }

        // Chat events — primary channel
        socket.on("events") { [weak self] data, ack in
            Task { @MainActor in
                self?.handleChatEvent(data, ack: ack)
            }
        }

        // Chat events — alternate channel name (some OWUI versions use this)
        socket.on("chat-events") { [weak self] data, ack in
            Task { @MainActor in
                self?.handleChatEvent(data, ack: ack)
            }
        }

        // Channel events — for group/channel messaging
        socket.on("events:channel") { [weak self] data, ack in
            Task { @MainActor in
                self?.handleChannelEvent(data, ack: ack)
            }
        }

        // Channel events — alternate channel name
        socket.on("channel-events") { [weak self] data, ack in
            Task { @MainActor in
                self?.handleChannelEvent(data, ack: ack)
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.socket?.emit("heartbeat", [:] as [String: Any])
            }
        }
    }

    // MARK: - Ack Wrapper

    /// Wraps a SocketAckEmitter into a simple closure that consumers can call.
    /// Returns nil if the server doesn't expect an acknowledgement.
    private func wrapAck(_ ack: SocketAckEmitter) -> (([Any]) -> Void)? {
        guard ack.expected else { return nil }
        return { items in ack.with(items) }
    }

    // MARK: - Event Parsing

    /// Extract a string value from nested dictionaries, checking both snake_case and camelCase keys.
    /// Searches top-level, then data.*, then data.data.* like Conduit does.
    private static func deepExtract(_ key: String, camelKey: String? = nil, from payload: [String: Any]) -> String? {
        // Top-level
        if let v = payload[key] as? String { return v }
        if let ck = camelKey, let v = payload[ck] as? String { return v }
        // data.*
        if let d = payload["data"] as? [String: Any] {
            if let v = d[key] as? String { return v }
            if let ck = camelKey, let v = d[ck] as? String { return v }
            // data.data.*
            if let dd = d["data"] as? [String: Any] {
                if let v = dd[key] as? String { return v }
                if let ck = camelKey, let v = dd[ck] as? String { return v }
            }
        }
        return nil
    }

    private func handleChatEvent(_ data: [Any], ack: SocketAckEmitter) {
        guard let payload = data.first as? [String: Any] else { return }

        // Deep extraction of IDs — checks top-level, data.*, data.data.* with both snake/camel keys
        let chatId = Self.deepExtract("chat_id", camelKey: "chatId", from: payload)
        let messageId = Self.deepExtract("message_id", camelKey: "messageId", from: payload) ?? ""

        guard let chatId else { return }

        let eventData = payload["data"] as? [String: Any] ?? payload
        let eventType = eventData["type"] as? String ?? payload["type"] as? String ?? "unknown"

        let innerData = eventData["data"] as? [String: Any] ?? eventData
        let ackFn = wrapAck(ack)
        onEvent?(chatId, messageId, eventType, innerData, ackFn)
    }

    private func handleChannelEvent(_ data: [Any], ack: SocketAckEmitter) {
        guard let payload = data.first as? [String: Any] else { return }

        let channelId = Self.deepExtract("channel_id", camelKey: "channelId", from: payload)
        let messageId = Self.deepExtract("message_id", camelKey: "messageId", from: payload)

        guard let channelId, let messageId else { return }

        let eventData = payload["data"] as? [String: Any] ?? payload
        let eventType = eventData["type"] as? String ?? payload["type"] as? String ?? "unknown"

        let innerData = eventData["data"] as? [String: Any] ?? eventData
        let ackFn = wrapAck(ack)
        onChannelEvent?(channelId, messageId, eventType, innerData, ackFn)
    }

    // MARK: - Parse Status Event

    /// Parse a raw status event dictionary into a StatusEvent model.
    static func parseStatusEvent(from data: [String: Any]) -> StatusEvent? {
        guard let action = data["action"] as? String else { return nil }

        let description = data["description"] as? String
        let done = data["done"] as? Bool ?? false
        let error = data["error"] as? Bool ?? false
        let queries = data["queries"] as? [String]
        let urls = data["urls"] as? [String]

        var items: [SearchResultItem]? = nil
        if let rawItems = data["items"] as? [[String: Any]] {
            items = rawItems.compactMap { item in
                guard let link = item["link"] as? String else { return nil }
                return SearchResultItem(
                    title: item["title"] as? String,
                    link: link,
                    snippet: item["snippet"] as? String
                )
            }
        }

        return StatusEvent(
            action: action,
            description: description,
            done: done,
            error: error,
            queries: queries,
            urls: urls,
            items: items
        )
    }
}
