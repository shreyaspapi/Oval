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
struct ServerConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var url: String              // e.g. "http://localhost:8080"
    var apiKey: String           // JWT token or sk-... API key
    var authMethod: AuthMethod = .apiKey
    var email: String?           // Only set when authMethod == .emailPassword
    var iconEmoji: String = "🌐" // Emoji shown in the server sidebar
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

struct AIModel: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String?
    let owned_by: String?

    var displayName: String {
        name ?? id
    }
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

struct ChatMessage: Codable, Identifiable, Equatable {
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

    init(model: String, messages: [CompletionMessage], stream: Bool, temperature: Double?, max_tokens: Int?, files: [CompletionFileRef]? = nil, features: ChatFeatures? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.files = files
        self.features = features
    }
}

/// File reference sent in the chat completion request body.
struct CompletionFileRef: Codable {
    let type: String   // "file"
    let id: String     // server file ID
}

/// A completion message with support for multimodal content.
/// `content` can be either a plain string or an array of content parts (text + images).
struct CompletionMessage: Codable {
    let role: String
    let content: MessageContent
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

/// A complete tool call assembled from streaming chunks.
struct ToolCall: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let function: ToolCallComplete

    struct ToolCallComplete: Codable, Equatable {
        let name: String
        let arguments: String
    }
}

struct TokenUsage: Codable {
    let prompt_tokens: Int?
    let completion_tokens: Int?
    let total_tokens: Int?
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
