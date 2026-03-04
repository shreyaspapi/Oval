import Combine
import Foundation
import SocketIO

/// Manages the Socket.IO connection to the Open WebUI server.
/// Receives real-time events (status updates, streaming content, sources)
/// that aren't available through the REST SSE endpoint.
@MainActor
final class SocketService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isConnected = false
    @Published private(set) var sessionId: String?

    // MARK: - Event Callback

    /// Called when a status/chat event is received for a specific message.
    /// Parameters: (chatId, messageId, eventType, eventData)
    var onEvent: ((_ chatId: String, _ messageId: String, _ type: String, _ data: [String: Any]) -> Void)?

    // MARK: - Private

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var serverURL: String?
    private var token: String?
    private var heartbeatTimer: Timer?

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
            }
        }

        // Listen for the "events" channel — all status/streaming events come here
        socket.on("events") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleEvent(data)
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

    // MARK: - Event Parsing

    private func handleEvent(_ data: [Any]) {
        guard let payload = data.first as? [String: Any],
              let chatId = payload["chat_id"] as? String,
              let messageId = payload["message_id"] as? String,
              let eventData = payload["data"] as? [String: Any],
              let eventType = eventData["type"] as? String
        else { return }

        let innerData = eventData["data"] as? [String: Any] ?? [:]
        onEvent?(chatId, messageId, eventType, innerData)
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
