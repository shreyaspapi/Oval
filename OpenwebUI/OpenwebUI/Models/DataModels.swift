import Foundation

// MARK: - Auth Method

/// How the user authenticated with the server.
enum AuthMethod: String, Codable, Equatable {
    case emailPassword  // Signed in with email + password, got JWT
    case apiKey         // Pasted an API key directly
    case sso            // Authenticated via SSO/OAuth WebView
}

// MARK: - Server

/// A saved Open WebUI server connection.
/// The API key / JWT token is stored securely in the macOS Keychain — never in the JSON config file.
struct ServerConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var url: String              // e.g. "http://localhost:8080"
    var apiKey: String           // JWT token or sk-... API key (stored in Keychain, not JSON)
    var authMethod: AuthMethod = .apiKey
    var email: String?           // Only set when authMethod == .emailPassword
    var iconEmoji: String = "🌐" // Emoji shown in the server sidebar

    // Custom coding keys — apiKey is excluded from JSON serialization.
    // It is stored in and loaded from the Keychain separately.
    enum CodingKeys: String, CodingKey {
        case id, name, url, authMethod, email, iconEmoji
    }

    init(id: UUID = UUID(), name: String, url: String, apiKey: String, authMethod: AuthMethod = .apiKey, email: String? = nil, iconEmoji: String = "🌐") {
        self.id = id
        self.name = name
        self.url = url
        self.apiKey = apiKey
        self.authMethod = authMethod
        self.email = email
        self.iconEmoji = iconEmoji
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        authMethod = try c.decodeIfPresent(AuthMethod.self, forKey: .authMethod) ?? .apiKey
        email = try c.decodeIfPresent(String.self, forKey: .email)
        iconEmoji = try c.decodeIfPresent(String.self, forKey: .iconEmoji) ?? "🌐"
        // apiKey is loaded from Keychain after decoding — default to empty string
        apiKey = ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(url, forKey: .url)
        try c.encode(authMethod, forKey: .authMethod)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encode(iconEmoji, forKey: .iconEmoji)
        // apiKey is NOT encoded — it lives in the Keychain
    }
}

// MARK: - Auth

struct SignInRequest: Codable {
    let email: String
    let password: String
}

/// Response from POST /api/v1/auths/signin
struct SignInResponse: Codable {
    let token: String
    let token_type: String?
    let expires_at: Int?
    let id: String
    let email: String
    let name: String
    let role: String
    let profile_image_url: String?
}

struct SessionUser: Codable {
    let token: String?
    let id: String
    let email: String
    let name: String
    let role: String
    let profile_image_url: String?
}

// MARK: - Models

struct ModelListResponse: Codable {
    let data: [AIModel]?
}

/// A model returned by the Open WebUI `/api/models` endpoint.
/// Captures the rich metadata the server provides: Ollama details, connection type,
/// tags, description, profile image, and more.
struct AIModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let owned_by: String?

    // Rich metadata from the server
    var connection_type: String?       // "local", "external", or nil
    var ollama: OllamaInfo?            // Ollama-specific details (parameter size, quant, loaded status)
    var info: OpenWebUIModelInfo?       // DB-level customization (description, profile image, tags, etc.)
    var tags: [ModelTag]?              // Merged tag list
    var preset: Bool?                  // True for user-created preset/custom models
    var pipe: PipeInfo?                // Present for function/pipe models

    init(id: String, name: String?, owned_by: String?,
         connection_type: String? = nil, ollama: OllamaInfo? = nil,
         info: OpenWebUIModelInfo? = nil, tags: [ModelTag]? = nil,
         preset: Bool? = nil, pipe: PipeInfo? = nil) {
        self.id = id
        self.name = name
        self.owned_by = owned_by
        self.connection_type = connection_type
        self.ollama = ollama
        self.info = info
        self.tags = tags
        self.preset = preset
        self.pipe = pipe
    }

    // MARK: - Computed Properties

    var displayName: String {
        // Prefer the customized name from `info`, then the top-level `name`, then the raw `id`
        if let customName = info?.name, !customName.isEmpty { return customName }
        return name ?? id
    }

    /// Short parameter size string, e.g. "7B", "70B", "13B"
    var parameterSize: String? {
        ollama?.details?.parameter_size
    }

    /// Quantization level, e.g. "Q4_0", "Q5_K_M"
    var quantizationLevel: String? {
        ollama?.details?.quantization_level
    }

    /// Model file size in bytes (Ollama models)
    var fileSize: Int? {
        ollama?.size
    }

    /// True if the Ollama model is currently loaded in memory
    var isLoaded: Bool {
        guard let expiresAt = ollama?.expires_at, expiresAt > 0 else { return false }
        return Date(timeIntervalSince1970: TimeInterval(expiresAt)) > Date()
    }

    /// Human-readable description from model info
    var descriptionText: String? {
        info?.meta?.description
    }

    /// Profile image URL path (relative to server base URL)
    var profileImagePath: String? {
        // The server strips profile_image_url from /api/models responses to save bandwidth.
        // Use the dedicated image endpoint instead.
        nil
    }

    /// Tag names as a flat string array
    var tagNames: [String] {
        tags?.map(\.name) ?? []
    }

    /// Connection category for filtering
    var connectionCategory: ModelConnectionCategory {
        switch connection_type {
        case "local":    return .local
        case "external": return .external
        default:
            // Infer from owned_by if connection_type is missing
            if owned_by == "ollama" { return .local }
            if owned_by == "openai" { return .external }
            return .unknown
        }
    }

    /// True for function/pipe models
    var isPipe: Bool { pipe != nil }

    /// True for user-created preset models
    var isPreset: Bool { preset ?? false }

    // MARK: - Equatable (by id only for performance)

    static func == (lhs: AIModel, rhs: AIModel) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Connection type categories for model filtering
enum ModelConnectionCategory: String, CaseIterable {
    case local
    case external
    case unknown
}

// MARK: - Ollama Sub-Models

/// Ollama-specific model information
struct OllamaInfo: Codable, Hashable {
    let name: String?
    let model: String?
    let modified_at: String?
    let size: Int?
    let digest: String?
    let details: OllamaDetails?
    let expires_at: Int?               // epoch timestamp — non-nil if model is loaded in memory

    static func == (lhs: OllamaInfo, rhs: OllamaInfo) -> Bool { lhs.digest == rhs.digest }
    func hash(into hasher: inout Hasher) { hasher.combine(digest) }
}

/// Ollama model details (family, parameter size, quantization)
struct OllamaDetails: Codable, Hashable {
    let parent_model: String?
    let format: String?
    let family: String?
    let families: [String]?
    let parameter_size: String?
    let quantization_level: String?
}

// MARK: - Model Info (DB customization)

/// Server-side model customization stored in the Open WebUI database.
/// Named `OpenWebUIModelInfo` to avoid collision with `RunAnywhere.ModelInfo`.
struct OpenWebUIModelInfo: Codable, Hashable {
    let id: String?
    let name: String?
    let base_model_id: String?
    let meta: ModelMeta?

    static func == (lhs: OpenWebUIModelInfo, rhs: OpenWebUIModelInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Model metadata: description, profile image, tags, suggestion prompts, capabilities
struct ModelMeta: Codable, Hashable {
    let profile_image_url: String?
    let description: String?
    let capabilities: ModelCapabilities?
    let tags: [ModelTag]?
    let suggestion_prompts: [SuggestionPrompt]?
    let hidden: Bool?

    static func == (lhs: ModelMeta, rhs: ModelMeta) -> Bool {
        lhs.description == rhs.description && lhs.profile_image_url == rhs.profile_image_url
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(description)
        hasher.combine(profile_image_url)
    }
}

struct ModelCapabilities: Codable, Hashable {
    let vision: Bool?
    let web_search: Bool?
    let image_generation: Bool?
    let code_interpreter: Bool?
}

struct SuggestionPrompt: Codable, Hashable {
    let content: String?
    let title: [String]?               // Usually [shortTitle, subtitle]
}

// MARK: - Model Tag

struct ModelTag: Codable, Hashable {
    let name: String
}

// MARK: - Pipe Info

struct PipeInfo: Codable, Hashable {
    let type: String?
}

// MARK: - Chat / Conversations

struct ChatListItem: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let updated_at: Double?
    let created_at: Double?

    var updatedDate: Date? {
        guard let ts = updated_at else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}

struct ChatResponse: Codable {
    let id: String
    let user_id: String?
    let title: String
    let chat: ChatData?
    let pinned: Bool?
    let archived: Bool?
    let updated_at: Double?
    let created_at: Double?
}

struct ChatData: Codable {
    let history: ChatHistory?
    let title: String?
}

struct ChatHistory: Codable {
    let messages: [String: ChatMessage]?
    let currentId: String?
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: String          // "user", "assistant", "system", "tool"
    let content: String
    let model: String?
    let timestamp: Double?
    let parentId: String?
    let childrenIds: [String]?
    /// Base64-encoded image data URIs attached to this message (data:image/...;base64,...)
    var images: [String]?
    /// Non-image file references attached to this message
    var files: [ChatFileRef]?
    /// Tool calls made by the assistant in this message
    var toolCalls: [ToolCall]?
    /// For tool role messages: the tool call ID this result is for
    var toolCallId: String?
    /// Status history (web search progress, etc.) — persisted on server and populated during streaming.
    var statusHistory: [StatusEvent]?
}

extension ChatMessage: Codable {
    enum CodingKeys: String, CodingKey {
        case id, role, content, model, timestamp, parentId, childrenIds
        case images, files, toolCalls, toolCallId, statusHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        role = try c.decode(String.self, forKey: .role)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model)
        timestamp = try c.decodeIfPresent(Double.self, forKey: .timestamp)
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        childrenIds = try c.decodeIfPresent([String].self, forKey: .childrenIds)
        images = try c.decodeIfPresent([String].self, forKey: .images)
        files = try c.decodeIfPresent([ChatFileRef].self, forKey: .files)
        toolCalls = try c.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        toolCallId = try c.decodeIfPresent(String.self, forKey: .toolCallId)
        // Decode statusHistory — the server stores raw JSON dicts, so decode manually
        statusHistory = try c.decodeIfPresent([StatusEventCodable].self, forKey: .statusHistory)?.map(\.toStatusEvent)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(timestamp, forKey: .timestamp)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encodeIfPresent(childrenIds, forKey: .childrenIds)
        try c.encodeIfPresent(images, forKey: .images)
        try c.encodeIfPresent(files, forKey: .files)
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try c.encodeIfPresent(toolCallId, forKey: .toolCallId)
        // Encode statusHistory back to the codable wrapper
        try c.encodeIfPresent(statusHistory?.map { StatusEventCodable(from: $0) }, forKey: .statusHistory)
    }
}

/// Reference to an uploaded file attached to a message.
struct ChatFileRef: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    let name: String
    let type: String          // MIME type
    let size: Int
    /// Server-side file ID after upload (from /api/v1/files/upload)
    let fileId: String?
}

// MARK: - Attachments (Local UI State)

/// A pending attachment selected by the user before sending.
struct PendingAttachment: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let mimeType: String
    let data: Data
    let isImage: Bool

    /// For images: data URI string (data:image/png;base64,...)
    var dataURI: String? {
        guard isImage else { return nil }
        let base64 = data.base64EncodedString()
        return "data:\(mimeType);base64,\(base64)"
    }

    static func == (lhs: PendingAttachment, rhs: PendingAttachment) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - File Upload Response

/// Response from POST /api/v1/files/upload
struct FileUploadResponse: Codable {
    let id: String
    let filename: String
    let meta: FileUploadMeta?
}

struct FileUploadMeta: Codable {
    let name: String?
    let content_type: String?
    let size: Int?
}

// MARK: - Chat Completions

/// Feature flags passed in the chat completion request (e.g. web search).
struct ChatFeatures: Codable {
    let web_search: Bool?

    init(web_search: Bool? = nil) {
        self.web_search = web_search
    }
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [CompletionMessage]
    let stream: Bool
    let temperature: Double?
    let max_tokens: Int?
    /// File IDs to include (for non-image files uploaded via /api/v1/files/)
    let files: [CompletionFileRef]?
    /// Feature flags (web search, etc.)
    let features: ChatFeatures?
    /// Socket.IO session ID — when set, server routes events via Socket.IO instead of SSE
    let session_id: String?
    /// Chat ID for Socket.IO event routing
    let chat_id: String?

    init(model: String, messages: [CompletionMessage], stream: Bool, temperature: Double?, max_tokens: Int?, files: [CompletionFileRef]? = nil, features: ChatFeatures? = nil, session_id: String? = nil, chat_id: String? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.files = files
        self.features = features
        self.session_id = session_id
        self.chat_id = chat_id
    }
}

/// File reference sent in the chat completion request body.
struct CompletionFileRef: Codable {
    let type: String   // "file"
    let id: String     // server file ID
}

/// A completion message with support for multimodal content and tool calls.
/// `content` can be either a plain string or an array of content parts (text + images).
struct CompletionMessage: Codable {
    let role: String
    let content: MessageContent
    /// Tool calls made by the assistant (included when role == "assistant")
    let tool_calls: [CompletionToolCall]?
    /// The tool call ID this message is a response to (included when role == "tool")
    let tool_call_id: String?

    init(role: String, content: MessageContent, tool_calls: [CompletionToolCall]? = nil, tool_call_id: String? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = tool_calls
        self.tool_call_id = tool_call_id
    }
}

/// Tool call reference in a completion message (OpenAI format).
struct CompletionToolCall: Codable {
    let id: String
    let type: String
    let function: CompletionToolCallFunction
}

struct CompletionToolCallFunction: Codable {
    let name: String
    let arguments: String
}

/// Content that encodes as either a string or an array of content parts.
/// This matches the OpenAI chat completions format.
enum MessageContent: Codable, Equatable {
    case text(String)
    case parts([ContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .parts(let parts):
            try container.encode(parts)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else {
            let parts = try container.decode([ContentPart].self)
            self = .parts(parts)
        }
    }
}

/// A content part in a multimodal message.
struct ContentPart: Codable, Equatable {
    let type: String        // "text" or "image_url"
    let text: String?       // present when type == "text"
    let image_url: ImageURL? // present when type == "image_url"

    static func text(_ string: String) -> ContentPart {
        ContentPart(type: "text", text: string, image_url: nil)
    }

    static func imageURL(_ url: String) -> ContentPart {
        ContentPart(type: "image_url", text: nil, image_url: ImageURL(url: url))
    }
}

struct ImageURL: Codable, Equatable {
    let url: String  // "data:image/png;base64,..." or a URL
}

struct ChatCompletionChunk: Codable {
    let id: String?
    let choices: [ChunkChoice]?
    let error: String?
    let usage: TokenUsage?
}

struct ChunkChoice: Codable {
    let delta: ChunkDelta?
    let index: Int?
    let finish_reason: String?
}

struct ChunkDelta: Codable {
    let content: String?
    let role: String?
    let tool_calls: [ToolCallChunk]?
}

// MARK: - Tool Calling

/// A tool call chunk received during streaming.
struct ToolCallChunk: Codable {
    let index: Int?
    let id: String?
    let type: String?
    let function: ToolCallFunction?
}

struct ToolCallFunction: Codable {
    let name: String?
    let arguments: String?
}

/// Execution status of a tool call.
enum ToolCallStatus: String, Codable, Equatable {
    case pending       // Streaming in, not yet complete
    case executing     // Server is executing the tool
    case completed     // Tool returned a result
    case error         // Tool execution failed
}

/// A complete tool call assembled from streaming chunks.
struct ToolCall: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let function: ToolCallComplete
    /// Current execution status
    var status: ToolCallStatus
    /// Result returned by the tool (populated when done)
    var result: String?
    /// Error message if the tool call failed
    var error: String?

    struct ToolCallComplete: Codable, Equatable {
        let name: String
        let arguments: String
    }

    init(id: String, type: String, function: ToolCallComplete, status: ToolCallStatus = .pending, result: String? = nil, error: String? = nil) {
        self.id = id
        self.type = type
        self.function = function
        self.status = status
        self.result = result
        self.error = error
    }
}

struct TokenUsage: Codable {
    let prompt_tokens: Int?
    let completion_tokens: Int?
    let total_tokens: Int?
}

// MARK: - Socket.IO Status Events

/// A status event received via Socket.IO during chat processing.
/// Tracks web search progress, knowledge search, and other server-side actions.
struct StatusEvent: Identifiable, Equatable {
    let id = UUID()
    let action: String            // "web_search", "web_search_queries_generated", "knowledge_search", etc.
    let description: String?
    let done: Bool
    let error: Bool
    let queries: [String]?        // Search queries generated by the model
    let urls: [String]?           // URLs that were searched
    let items: [SearchResultItem]? // Search result items (title + link + snippet)
}

/// A single web search result item.
struct SearchResultItem: Identifiable, Equatable, Codable {
    var id: String { link }
    let title: String?
    let link: String
    let snippet: String?

    enum CodingKeys: String, CodingKey {
        case title, link, url, snippet
    }

    init(title: String?, link: String, snippet: String?) {
        self.title = title
        self.link = link
        self.snippet = snippet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        // Server may use "link" or "url"
        link = try c.decodeIfPresent(String.self, forKey: .link)
            ?? c.decodeIfPresent(String.self, forKey: .url)
            ?? ""
        snippet = try c.decodeIfPresent(String.self, forKey: .snippet)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(link, forKey: .link)
        try c.encodeIfPresent(snippet, forKey: .snippet)
    }
}

/// Codable wrapper for StatusEvent to handle server JSON format.
struct StatusEventCodable: Codable {
    let action: String
    let description: String?
    let done: Bool?
    let error: Bool?
    let queries: [String]?
    let urls: [String]?
    let items: [SearchResultItem]?
    let query: String?
    let hidden: Bool?

    var toStatusEvent: StatusEvent {
        StatusEvent(
            action: action,
            description: description,
            done: done ?? false,
            error: error ?? false,
            queries: queries,
            urls: urls,
            items: items
        )
    }

    init(from statusEvent: StatusEvent) {
        self.action = statusEvent.action
        self.description = statusEvent.description
        self.done = statusEvent.done
        self.error = statusEvent.error
        self.queries = statusEvent.queries
        self.urls = statusEvent.urls
        self.items = statusEvent.items
        self.query = nil
        self.hidden = nil
    }
}

/// The top-level envelope for a Socket.IO "events" emit.
struct SocketEventEnvelope {
    let chatId: String
    let messageId: String
    let type: String              // "status", "chat:completion", "source", "message", "replace", etc.
    let data: [String: Any]       // The inner data payload
}

/// Source/citation data received via Socket.IO.
struct SourceEvent: Equatable, Identifiable {
    let id = UUID()
    let name: String
    let url: String?
    let title: String?
    let snippet: String?
}

// MARK: - Title Generation

/// Request body for POST /api/v1/tasks/title/completions
struct TitleGenerationRequest: Codable {
    let model: String
    let messages: [TitleGenerationMessage]
    let chat_id: String?
}

/// Simplified message for title generation (just role + content).
struct TitleGenerationMessage: Codable {
    let role: String
    let content: String
}

/// Non-streaming chat completion response (used for title generation).
struct ChatCompletionResponse: Codable {
    let id: String?
    let choices: [CompletionChoice]?
}

struct CompletionChoice: Codable {
    let message: CompletionResponseMessage?
    let index: Int?
    let finish_reason: String?
}

struct CompletionResponseMessage: Codable {
    let role: String?
    let content: String?
}

// MARK: - New / Update Chat

/// Request body for POST /api/v1/chats/new
struct NewChatRequest: Codable {
    let chat: ChatBlob
}

/// Request body for POST /api/v1/chats/{id}
struct UpdateChatRequest: Codable {
    let chat: ChatBlob
}

/// The full chat state blob sent to the server.
/// Matches the web frontend's structure: title, history (message tree), flat messages list.
struct ChatBlob: Codable {
    let title: String
    let history: ChatBlobHistory
    let messages: [ChatBlobMessage]
    let timestamp: Double?

    init(title: String, history: ChatBlobHistory, messages: [ChatBlobMessage], timestamp: Double? = nil) {
        self.title = title
        self.history = history
        self.messages = messages
        self.timestamp = timestamp ?? Date().timeIntervalSince1970 * 1000
    }
}

/// History tree stored in the chat blob.
struct ChatBlobHistory: Codable {
    let messages: [String: ChatBlobMessage]
    let currentId: String?
}

/// A message stored in the chat blob (server-side persistence format).
struct ChatBlobMessage: Codable {
    let id: String
    let role: String
    let content: String
    let model: String?
    let parentId: String?
    let childrenIds: [String]
    let timestamp: Double?
    let images: [String]?
    let files: [ChatFileRef]?
    /// Tool calls made by the assistant (persisted for reload)
    let toolCalls: [ToolCall]?
    /// For tool role messages: the ID of the tool call this result is for
    let toolCallId: String?
    /// Status history (web search progress events, etc.) — must be preserved on save
    let statusHistory: [StatusEventCodable]?
}

// MARK: - Helpers

extension ChatHistory {
    /// Flatten the tree into a linear message list following the currentId chain.
    func linearMessages() -> [ChatMessage] {
        guard let messages, let currentId else { return [] }

        // Walk from currentId up to root via parentId
        var chain: [ChatMessage] = []
        var nodeId: String? = currentId
        while let nid = nodeId, let msg = messages[nid] {
            chain.append(msg)
            nodeId = msg.parentId
        }
        return chain.reversed()
    }
}
