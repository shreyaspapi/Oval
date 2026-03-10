import Testing
import Foundation
@testable import Oval

// MARK: - AuthMethod Tests

@Suite("AuthMethod")
struct AuthMethodTests {

    @Test("raw values match expected strings")
    func rawValues() {
        #expect(AuthMethod.emailPassword.rawValue == "emailPassword")
        #expect(AuthMethod.apiKey.rawValue == "apiKey")
        #expect(AuthMethod.sso.rawValue == "sso")
    }

    @Test("round-trip JSON encoding/decoding")
    func jsonRoundTrip() throws {
        for method in [AuthMethod.emailPassword, .apiKey, .sso] {
            let data = try JSONEncoder().encode(method)
            let decoded = try JSONDecoder().decode(AuthMethod.self, from: data)
            #expect(decoded == method)
        }
    }
}

// MARK: - ServerConfig Tests

@Suite("ServerConfig")
struct ServerConfigTests {

    @Test("init sets all fields correctly")
    func initFields() {
        let id = UUID()
        let server = ServerConfig(
            id: id,
            name: "Test Server",
            url: "http://localhost:8080",
            apiKey: "sk-test-key",
            authMethod: .apiKey,
            email: nil,
            iconEmoji: "🔵"
        )
        #expect(server.id == id)
        #expect(server.name == "Test Server")
        #expect(server.url == "http://localhost:8080")
        #expect(server.apiKey == "sk-test-key")
        #expect(server.authMethod == .apiKey)
        #expect(server.email == nil)
        #expect(server.iconEmoji == "🔵")
    }

    @Test("default values")
    func defaults() {
        let server = ServerConfig(name: "S", url: "http://x", apiKey: "k")
        #expect(server.authMethod == .apiKey)
        #expect(server.email == nil)
        #expect(server.iconEmoji == "🌐")
    }

    @Test("encoding excludes apiKey from JSON")
    func encodingExcludesApiKey() throws {
        let server = ServerConfig(name: "S", url: "http://x", apiKey: "secret-key-123")
        let data = try JSONEncoder().encode(server)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["apiKey"] == nil, "apiKey must not appear in encoded JSON")
        #expect(json["name"] as? String == "S")
        #expect(json["url"] as? String == "http://x")
    }

    @Test("decoding sets apiKey to empty string")
    func decodingApiKeyEmpty() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Decoded Server",
            "url": "http://test:8080"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let server = try JSONDecoder().decode(ServerConfig.self, from: data)
        #expect(server.apiKey == "")
        #expect(server.name == "Decoded Server")
    }

    @Test("decoding with authMethod")
    func decodingAuthMethod() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "name": "SSO Server",
            "url": "http://sso:8080",
            "authMethod": "sso"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let server = try JSONDecoder().decode(ServerConfig.self, from: data)
        #expect(server.authMethod == .sso)
    }

    @Test("decoding defaults authMethod to apiKey when missing")
    func decodingDefaultAuthMethod() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Old Server",
            "url": "http://old:8080"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let server = try JSONDecoder().decode(ServerConfig.self, from: data)
        #expect(server.authMethod == .apiKey)
    }

    @Test("Equatable compares all fields")
    func equatable() {
        let id = UUID()
        let a = ServerConfig(id: id, name: "A", url: "http://a", apiKey: "k1")
        let b = ServerConfig(id: id, name: "A", url: "http://a", apiKey: "k1")
        let c = ServerConfig(id: UUID(), name: "A", url: "http://a", apiKey: "k1")
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - SignInRequest / SignInResponse Tests

@Suite("Auth Request/Response Models")
struct AuthModelTests {

    @Test("SignInRequest encodes correctly")
    func signInRequestEncoding() throws {
        let req = SignInRequest(email: "test@example.com", password: "pass123")
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["email"] as? String == "test@example.com")
        #expect(json["password"] as? String == "pass123")
    }

    @Test("SignInResponse decodes correctly")
    func signInResponseDecoding() throws {
        let json: [String: Any] = [
            "token": "jwt-token-123",
            "token_type": "Bearer",
            "id": "user-1",
            "email": "admin@test.com",
            "name": "Admin",
            "role": "admin",
            "profile_image_url": "https://example.com/avatar.png"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try JSONDecoder().decode(SignInResponse.self, from: data)
        #expect(response.token == "jwt-token-123")
        #expect(response.id == "user-1")
        #expect(response.email == "admin@test.com")
        #expect(response.name == "Admin")
        #expect(response.role == "admin")
    }

    @Test("SessionUser decodes correctly")
    func sessionUserDecoding() throws {
        let json: [String: Any] = [
            "id": "user-2",
            "email": "user@test.com",
            "name": "Test User",
            "role": "user"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let user = try JSONDecoder().decode(SessionUser.self, from: data)
        #expect(user.id == "user-2")
        #expect(user.token == nil)
        #expect(user.name == "Test User")
    }
}

// MARK: - AIModel Tests

@Suite("AIModel")
struct AIModelTests {

    nonisolated static func makeModel(
        id: String = "llama3:latest",
        name: String? = "Llama 3",
        owned_by: String? = "ollama",
        connection_type: String? = "local",
        ollama: OllamaInfo? = nil,
        info: OpenWebUIModelInfo? = nil
    ) -> AIModel {
        AIModel(id: id, name: name, owned_by: owned_by,
                connection_type: connection_type, ollama: ollama, info: info)
    }

    @Test("displayName prefers info.name, then name, then id")
    func displayName() {
        let m1 = Self.makeModel(name: "Llama 3", info: OpenWebUIModelInfo(id: nil, name: "Custom Name", base_model_id: nil, meta: nil))
        #expect(m1.displayName == "Custom Name")

        let m2 = Self.makeModel(name: "Llama 3", info: nil)
        #expect(m2.displayName == "Llama 3")

        let m3 = Self.makeModel(id: "model-id", name: nil, info: nil)
        #expect(m3.displayName == "model-id")
    }

    @Test("connectionCategory from connection_type")
    func connectionCategory() {
        #expect(Self.makeModel(connection_type: "local").connectionCategory == .local)
        #expect(Self.makeModel(connection_type: "external").connectionCategory == .external)
        #expect(Self.makeModel(owned_by: "ollama", connection_type: nil).connectionCategory == .local)
        #expect(Self.makeModel(owned_by: "openai", connection_type: nil).connectionCategory == .external)
        #expect(Self.makeModel(owned_by: "other", connection_type: nil).connectionCategory == .unknown)
    }

    @Test("parameterSize and quantizationLevel from Ollama details")
    func ollamaDetails() {
        let details = OllamaDetails(parent_model: nil, format: "gguf", family: "llama", families: nil, parameter_size: "7B", quantization_level: "Q4_0")
        let ollama = OllamaInfo(name: "llama3", model: "llama3:latest", modified_at: nil, size: 4_000_000_000, digest: "abc123", details: details, expires_at: nil)
        let model = Self.makeModel(ollama: ollama)
        #expect(model.parameterSize == "7B")
        #expect(model.quantizationLevel == "Q4_0")
        #expect(model.fileSize == 4_000_000_000)
    }

    @Test("isLoaded checks expires_at in the future")
    func isLoaded() {
        let futureTS = Int(Date().timeIntervalSince1970) + 3600
        let pastTS = Int(Date().timeIntervalSince1970) - 3600

        let loadedOllama = OllamaInfo(name: nil, model: nil, modified_at: nil, size: nil, digest: nil, details: nil, expires_at: futureTS)
        let unloadedOllama = OllamaInfo(name: nil, model: nil, modified_at: nil, size: nil, digest: nil, details: nil, expires_at: pastTS)
        let noExpiry = OllamaInfo(name: nil, model: nil, modified_at: nil, size: nil, digest: nil, details: nil, expires_at: nil)

        #expect(Self.makeModel(ollama: loadedOllama).isLoaded == true)
        #expect(Self.makeModel(ollama: unloadedOllama).isLoaded == false)
        #expect(Self.makeModel(ollama: noExpiry).isLoaded == false)
    }

    @Test("isPipe and isPreset")
    func pipeAndPreset() {
        let pipeModel = AIModel(id: "pipe", name: nil, owned_by: nil, pipe: PipeInfo(type: "function"))
        #expect(pipeModel.isPipe == true)
        #expect(pipeModel.isPreset == false)

        let presetModel = AIModel(id: "preset", name: nil, owned_by: nil, preset: true)
        #expect(presetModel.isPreset == true)
        #expect(presetModel.isPipe == false)
    }

    @Test("Equatable by id only")
    func equatableById() {
        let a = AIModel(id: "same-id", name: "A", owned_by: nil)
        let b = AIModel(id: "same-id", name: "B", owned_by: nil)
        #expect(a == b)
    }

    @Test("Hashable by id only")
    func hashableById() {
        let a = AIModel(id: "hash-id", name: "A", owned_by: nil)
        let b = AIModel(id: "hash-id", name: "B", owned_by: nil)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("tagNames returns flat array")
    func tagNames() {
        let model = AIModel(id: "t", name: nil, owned_by: nil, tags: [ModelTag(name: "coding"), ModelTag(name: "general")])
        #expect(model.tagNames == ["coding", "general"])
    }

    @Test("JSON round-trip")
    func jsonRoundTrip() throws {
        let model = AIModel(id: "test-model", name: "Test", owned_by: "ollama", connection_type: "local")
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(AIModel.self, from: data)
        #expect(decoded.id == model.id)
        #expect(decoded.name == model.name)
    }
}

// MARK: - ChatListItem Tests

@Suite("ChatListItem")
struct ChatListItemTests {

    @Test("updatedDate conversion")
    func updatedDate() {
        let ts: Double = 1700000000
        let item = ChatListItem(id: "1", title: "Chat", updated_at: ts, created_at: ts)
        #expect(item.updatedDate != nil)
        #expect(item.updatedDate == Date(timeIntervalSince1970: ts))
    }

    @Test("updatedDate nil when updated_at is nil")
    func updatedDateNil() {
        let item = ChatListItem(id: "1", title: "Chat", updated_at: nil, created_at: nil)
        #expect(item.updatedDate == nil)
    }

    @Test("isPinned defaults to false")
    func isPinnedDefault() {
        let item = ChatListItem(id: "1", title: "Chat", updated_at: nil, created_at: nil)
        #expect(item.isPinned == false)
    }

    @Test("isPinned reflects pinned field")
    func isPinnedTrue() {
        let item = ChatListItem(id: "1", title: "Chat", updated_at: nil, created_at: nil, pinned: true)
        #expect(item.isPinned == true)
    }
}

// MARK: - MessageContent Tests

@Suite("MessageContent")
struct MessageContentTests {

    @Test("text encoding produces a string")
    func textEncoding() throws {
        let content = MessageContent.text("Hello world")
        let data = try JSONEncoder().encode(content)
        let str = String(data: data, encoding: .utf8)!
        #expect(str.contains("Hello world"))
    }

    @Test("text decoding from string")
    func textDecoding() throws {
        let data = "\"Hello from JSON\"".data(using: .utf8)!
        let content = try JSONDecoder().decode(MessageContent.self, from: data)
        if case .text(let str) = content {
            #expect(str == "Hello from JSON")
        } else {
            Issue.record("Expected .text case")
        }
    }

    @Test("parts encoding produces array")
    func partsEncoding() throws {
        let parts: [ContentPart] = [
            .text("Describe this image"),
            .imageURL("data:image/png;base64,abc123")
        ]
        let content = MessageContent.parts(parts)
        let data = try JSONEncoder().encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        #expect(json.count == 2)
        #expect(json[0]["type"] as? String == "text")
        #expect(json[1]["type"] as? String == "image_url")
    }

    @Test("parts round-trip")
    func partsRoundTrip() throws {
        let parts: [ContentPart] = [
            .text("Analyze"),
            .imageURL("https://example.com/img.png")
        ]
        let content = MessageContent.parts(parts)
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MessageContent.self, from: data)
        if case .parts(let decodedParts) = decoded {
            #expect(decodedParts.count == 2)
        } else {
            Issue.record("Expected .parts case")
        }
    }
}

// MARK: - ChatMessage Tests

@Suite("ChatMessage")
struct ChatMessageTests {

    @Test("basic init")
    func basicInit() {
        let msg = ChatMessage(
            id: "msg-1",
            role: "user",
            content: "Hello",
            model: nil,
            timestamp: 1700000000,
            parentId: nil,
            childrenIds: nil
        )
        #expect(msg.id == "msg-1")
        #expect(msg.role == "user")
        #expect(msg.content == "Hello")
    }

    @Test("Equatable")
    func equatable() {
        let a = ChatMessage(id: "1", role: "user", content: "Hi", model: nil, timestamp: nil, parentId: nil, childrenIds: nil)
        let b = ChatMessage(id: "1", role: "user", content: "Hi", model: nil, timestamp: nil, parentId: nil, childrenIds: nil)
        #expect(a == b)
    }

    @Test("JSON round-trip")
    func jsonRoundTrip() throws {
        var msg = ChatMessage(
            id: "msg-rt",
            role: "assistant",
            content: "Hello!",
            model: "llama3",
            timestamp: 1700000000,
            parentId: "parent-1",
            childrenIds: ["child-1"]
        )
        msg.images = ["data:image/png;base64,abc"]
        msg.files = [ChatFileRef(name: "doc.pdf", type: "application/pdf", size: 1024, fileId: "f-1")]

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.id == "msg-rt")
        #expect(decoded.role == "assistant")
        #expect(decoded.content == "Hello!")
        #expect(decoded.model == "llama3")
        #expect(decoded.images?.count == 1)
        #expect(decoded.files?.count == 1)
    }

    @Test("decoding with missing content defaults to empty string")
    func decodingMissingContent() throws {
        let json: [String: Any] = [
            "id": "no-content",
            "role": "user"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let msg = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(msg.content == "")
    }
}

// MARK: - ChatHistory Tests

@Suite("ChatHistory")
struct ChatHistoryTests {

    @Test("linearMessages walks the tree correctly")
    func linearMessages() {
        let msg1 = ChatMessage(id: "1", role: "user", content: "Hi", model: nil, timestamp: nil, parentId: nil, childrenIds: ["2"])
        let msg2 = ChatMessage(id: "2", role: "assistant", content: "Hello!", model: nil, timestamp: nil, parentId: "1", childrenIds: ["3"])
        let msg3 = ChatMessage(id: "3", role: "user", content: "How are you?", model: nil, timestamp: nil, parentId: "2", childrenIds: nil)

        let history = ChatHistory(messages: ["1": msg1, "2": msg2, "3": msg3], currentId: "3")
        let linear = history.linearMessages()
        #expect(linear.count == 3)
        #expect(linear[0].id == "1")
        #expect(linear[1].id == "2")
        #expect(linear[2].id == "3")
    }

    @Test("linearMessages returns empty for nil currentId")
    func linearMessagesNilCurrentId() {
        let history = ChatHistory(messages: [:], currentId: nil)
        #expect(history.linearMessages().isEmpty)
    }

    @Test("linearMessages returns empty for nil messages")
    func linearMessagesNilMessages() {
        let history = ChatHistory(messages: nil, currentId: "1")
        #expect(history.linearMessages().isEmpty)
    }
}

// MARK: - PendingAttachment Tests

@Suite("PendingAttachment")
struct PendingAttachmentTests {

    @Test("dataURI for image attachment")
    func dataURIImage() {
        let data = "fake-image-data".data(using: .utf8)!
        let attachment = PendingAttachment(fileName: "test.png", mimeType: "image/png", data: data, isImage: true)
        #expect(attachment.dataURI != nil)
        #expect(attachment.dataURI!.hasPrefix("data:image/png;base64,"))
    }

    @Test("dataURI nil for non-image attachment")
    func dataURINonImage() {
        let data = "file-data".data(using: .utf8)!
        let attachment = PendingAttachment(fileName: "doc.pdf", mimeType: "application/pdf", data: data, isImage: false)
        #expect(attachment.dataURI == nil)
    }

    @Test("Equatable by id")
    func equatable() {
        let data = Data()
        let a = PendingAttachment(fileName: "a.png", mimeType: "image/png", data: data, isImage: true)
        let b = PendingAttachment(fileName: "a.png", mimeType: "image/png", data: data, isImage: true)
        // Each has a unique UUID, so they should NOT be equal
        #expect(a != b)
        #expect(a == a)
    }
}

// MARK: - ToolCall Tests

@Suite("ToolCall")
struct ToolCallTests {

    @Test("ToolCallStatus raw values")
    func statusRawValues() {
        #expect(ToolCallStatus.pending.rawValue == "pending")
        #expect(ToolCallStatus.executing.rawValue == "executing")
        #expect(ToolCallStatus.completed.rawValue == "completed")
        #expect(ToolCallStatus.error.rawValue == "error")
    }

    @Test("ToolCall init and JSON round-trip")
    func roundTrip() throws {
        let tc = ToolCall(
            id: "tc-1",
            type: "function",
            function: ToolCall.ToolCallComplete(name: "web_search", arguments: "{\"query\": \"test\"}"),
            status: .completed,
            result: "Search results here"
        )
        let data = try JSONEncoder().encode(tc)
        let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
        #expect(decoded.id == "tc-1")
        #expect(decoded.function.name == "web_search")
        #expect(decoded.status == .completed)
        #expect(decoded.result == "Search results here")
    }
}

// MARK: - ModelConnectionCategory Tests

@Suite("ModelConnectionCategory")
struct ModelConnectionCategoryTests {

    @Test("allCases")
    func allCases() {
        #expect(ModelConnectionCategory.allCases.count == 3)
        #expect(ModelConnectionCategory.allCases.contains(.local))
        #expect(ModelConnectionCategory.allCases.contains(.external))
        #expect(ModelConnectionCategory.allCases.contains(.unknown))
    }
}

// MARK: - ChatCompletionRequest Tests

@Suite("ChatCompletionRequest")
struct ChatCompletionRequestTests {

    @Test("encoding includes all fields")
    func encoding() throws {
        let req = ChatCompletionRequest(
            model: "llama3:latest",
            messages: [CompletionMessage(role: "user", content: .text("Hello"))],
            stream: true,
            temperature: 0.7,
            max_tokens: 2048,
            features: ChatFeatures(web_search: true),
            session_id: "sid-123",
            chat_id: "chat-456"
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["model"] as? String == "llama3:latest")
        #expect(json["stream"] as? Bool == true)
        #expect(json["temperature"] as? Double == 0.7)
        #expect(json["session_id"] as? String == "sid-123")
        #expect(json["chat_id"] as? String == "chat-456")
    }
}

// MARK: - SearchResultItem Tests

@Suite("SearchResultItem")
struct SearchResultItemTests {

    @Test("decodes with 'link' key")
    func decodesWithLink() throws {
        let json: [String: Any] = [
            "title": "Test Result",
            "link": "https://example.com",
            "snippet": "A test snippet"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let item = try JSONDecoder().decode(SearchResultItem.self, from: data)
        #expect(item.link == "https://example.com")
        #expect(item.title == "Test Result")
    }

    @Test("decodes with 'url' key fallback")
    func decodesWithUrl() throws {
        let json: [String: Any] = [
            "title": "URL Result",
            "url": "https://fallback.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let item = try JSONDecoder().decode(SearchResultItem.self, from: data)
        #expect(item.link == "https://fallback.com")
    }
}
