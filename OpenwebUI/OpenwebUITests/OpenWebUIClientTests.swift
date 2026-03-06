import Testing
import Foundation
@testable import Oval

// MARK: - OpenWebUIClient Initialization Tests

@Suite("OpenWebUIClient Initialization")
struct OpenWebUIClientInitTests {

    @Test("init strips trailing slash from baseURL")
    func stripsTrailingSlash() async {
        let client = OpenWebUIClient(baseURL: "http://localhost:8080/", apiKey: "key")
        #expect(await client.baseURL == "http://localhost:8080")
    }

    @Test("init preserves baseURL without trailing slash")
    func preservesURL() async {
        let client = OpenWebUIClient(baseURL: "http://localhost:8080", apiKey: "key")
        #expect(await client.baseURL == "http://localhost:8080")
    }

    @Test("init stores apiKey")
    func storesApiKey() async {
        let client = OpenWebUIClient(baseURL: "http://localhost", apiKey: "my-secret-key")
        #expect(await client.apiKey == "my-secret-key")
    }

    @Test("init handles https URLs")
    func httpsURL() async {
        let client = OpenWebUIClient(baseURL: "https://remote.server.com/", apiKey: "key")
        #expect(await client.baseURL == "https://remote.server.com")
    }

    @Test("init handles complex URLs with port")
    func complexURL() async {
        let client = OpenWebUIClient(baseURL: "http://192.168.1.100:3000", apiKey: "k")
        #expect(await client.baseURL == "http://192.168.1.100:3000")
    }
}

// MARK: - StreamDelta Tests

@Suite("OpenWebUIClient.StreamDelta")
struct StreamDeltaTests {

    @Test("StreamDelta.content case carries text")
    func contentCase() {
        let delta = OpenWebUIClient.StreamDelta.content("Hello")
        if case .content(let text) = delta {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected .content case")
        }
    }

    @Test("StreamDelta.done case exists")
    func doneCase() {
        let delta = OpenWebUIClient.StreamDelta.done
        if case .done = delta {
            // pass
        } else {
            Issue.record("Expected .done case")
        }
    }

    @Test("StreamDelta.toolCall case carries chunk")
    func toolCallCase() {
        let chunk = ToolCallChunk(index: 0, id: "tc-1", type: "function", function: ToolCallFunction(name: "search", arguments: "{}"))
        let delta = OpenWebUIClient.StreamDelta.toolCall(chunk)
        if case .toolCall(let tc) = delta {
            #expect(tc.index == 0)
            #expect(tc.id == "tc-1")
        } else {
            Issue.record("Expected .toolCall case")
        }
    }
}

// MARK: - Request/Response Model Tests

@Suite("API Request Models")
struct APIRequestModelTests {

    @Test("CompletionMessage text encoding")
    func completionMessageText() throws {
        let msg = CompletionMessage(role: "user", content: .text("Hello"))
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["role"] as? String == "user")
        #expect(json["content"] as? String == "Hello")
    }

    @Test("CompletionMessage multimodal encoding")
    func completionMessageMultimodal() throws {
        let parts: [ContentPart] = [
            .text("Describe this"),
            .imageURL("data:image/png;base64,abc")
        ]
        let msg = CompletionMessage(role: "user", content: .parts(parts))
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["role"] as? String == "user")
        // Content should be an array for multimodal
        #expect(json["content"] is [[String: Any]])
    }

    @Test("CompletionMessage with tool_calls")
    func completionMessageWithToolCalls() throws {
        let tc = CompletionToolCall(id: "tc-1", type: "function", function: CompletionToolCallFunction(name: "search", arguments: "{}"))
        let msg = CompletionMessage(role: "assistant", content: .text("Searching..."), tool_calls: [tc])
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["tool_calls"] != nil)
        let toolCallsArr = json["tool_calls"] as? [[String: Any]]
        #expect(toolCallsArr?.count == 1)
        #expect(toolCallsArr?[0]["id"] as? String == "tc-1")
    }

    @Test("CompletionMessage with tool_call_id for tool role")
    func completionMessageToolRole() throws {
        let msg = CompletionMessage(role: "tool", content: .text("Result"), tool_call_id: "tc-1")
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["role"] as? String == "tool")
        #expect(json["tool_call_id"] as? String == "tc-1")
    }

    @Test("ChatCompletionRequest encoding")
    func chatCompletionRequest() throws {
        let req = ChatCompletionRequest(
            model: "llama3",
            messages: [CompletionMessage(role: "user", content: .text("Hi"))],
            stream: true,
            temperature: 0.8,
            max_tokens: 4096,
            files: [CompletionFileRef(type: "file", id: "f-1")],
            features: ChatFeatures(web_search: true),
            session_id: "sess-1",
            chat_id: "chat-1"
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["model"] as? String == "llama3")
        #expect(json["stream"] as? Bool == true)
        #expect(json["temperature"] as? Double == 0.8)
        #expect(json["max_tokens"] as? Int == 4096)
        #expect(json["session_id"] as? String == "sess-1")
        #expect(json["chat_id"] as? String == "chat-1")

        let files = json["files"] as? [[String: Any]]
        #expect(files?.count == 1)
        #expect(files?[0]["id"] as? String == "f-1")

        let features = json["features"] as? [String: Any]
        #expect(features?["web_search"] as? Bool == true)
    }

    @Test("ChatCompletionRequest nil optionals excluded")
    func chatCompletionRequestNils() throws {
        let req = ChatCompletionRequest(
            model: "m",
            messages: [],
            stream: false,
            temperature: 0.7,
            max_tokens: nil,
            files: nil,
            features: nil,
            session_id: nil,
            chat_id: nil
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["max_tokens"] == nil)
        #expect(json["files"] == nil)
        #expect(json["features"] == nil)
        #expect(json["session_id"] == nil)
        #expect(json["chat_id"] == nil)
    }

    @Test("CompletionFileRef encoding")
    func completionFileRef() throws {
        let ref = CompletionFileRef(type: "file", id: "file-abc-123")
        let data = try JSONEncoder().encode(ref)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "file")
        #expect(json["id"] as? String == "file-abc-123")
    }

    @Test("ChatFeatures encoding")
    func chatFeatures() throws {
        let features = ChatFeatures(web_search: true)
        let data = try JSONEncoder().encode(features)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["web_search"] as? Bool == true)
    }

    @Test("NewChatRequest encoding")
    func newChatRequest() throws {
        let blob = ChatBlob(
            title: "Test Chat",
            history: ChatBlobHistory(messages: [:], currentId: nil),
            messages: []
        )
        let req = NewChatRequest(chat: blob)
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let chat = json["chat"] as? [String: Any]
        #expect(chat?["title"] as? String == "Test Chat")
    }

    @Test("SignInRequest encoding")
    func signInRequest() throws {
        let req = SignInRequest(email: "user@test.com", password: "secret")
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["email"] as? String == "user@test.com")
        #expect(json["password"] as? String == "secret")
    }
}

// MARK: - Response Model Tests

@Suite("API Response Models")
struct APIResponseModelTests {

    @Test("SignInResponse decoding")
    func signInResponse() throws {
        let json: [String: Any] = [
            "token": "jwt-token",
            "token_type": "Bearer",
            "id": "u-1",
            "email": "test@test.com",
            "name": "Test",
            "role": "user",
            "profile_image_url": "https://img.com/pic.png"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let resp = try JSONDecoder().decode(SignInResponse.self, from: data)
        #expect(resp.token == "jwt-token")
        #expect(resp.id == "u-1")
    }

    @Test("ModelListResponse decoding")
    func modelListResponse() throws {
        let json: [String: Any] = [
            "data": [
                ["id": "model-1", "name": "Model 1"],
                ["id": "model-2", "name": "Model 2"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let resp = try JSONDecoder().decode(ModelListResponse.self, from: data)
        #expect(resp.data?.count == 2)
        #expect(resp.data?[0].id == "model-1")
    }

    @Test("ModelListResponse with nil data")
    func modelListResponseNil() throws {
        let json: [String: Any] = [:]
        let data = try JSONSerialization.data(withJSONObject: json)
        let resp = try JSONDecoder().decode(ModelListResponse.self, from: data)
        #expect(resp.data == nil)
    }

    @Test("ChatResponse decoding")
    func chatResponse() throws {
        let json: [String: Any] = [
            "id": "chat-123",
            "title": "My Chat",
            "updated_at": 1700000000.0,
            "created_at": 1699999000.0
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let resp = try JSONDecoder().decode(ChatResponse.self, from: data)
        #expect(resp.id == "chat-123")
        #expect(resp.title == "My Chat")
    }

    @Test("ChatCompletionChunk decoding with content")
    func chunkDecoding() throws {
        let json: [String: Any] = [
            "choices": [
                [
                    "delta": [
                        "content": "Hello"
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
        #expect(chunk.choices?.first?.delta?.content == "Hello")
        #expect(chunk.error == nil)
    }

    @Test("ChatCompletionChunk decoding with error")
    func chunkErrorDecoding() throws {
        let json: [String: Any] = [
            "error": "Rate limit exceeded"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
        #expect(chunk.error == "Rate limit exceeded")
    }

    @Test("ToolCallChunk decoding")
    func toolCallChunkDecoding() throws {
        let json: [String: Any] = [
            "index": 0,
            "id": "tc-1",
            "type": "function",
            "function": [
                "name": "search",
                "arguments": "{\"q\": \"test\"}"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let chunk = try JSONDecoder().decode(ToolCallChunk.self, from: data)
        #expect(chunk.index == 0)
        #expect(chunk.id == "tc-1")
        #expect(chunk.function?.name == "search")
        #expect(chunk.function?.arguments == "{\"q\": \"test\"}")
    }

    @Test("FileUploadResponse decoding")
    func fileUploadResponse() throws {
        let json: [String: Any] = [
            "id": "file-123",
            "filename": "document.pdf"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let resp = try JSONDecoder().decode(FileUploadResponse.self, from: data)
        #expect(resp.id == "file-123")
        #expect(resp.filename == "document.pdf")
    }

    @Test("SessionUser decoding with all fields")
    func sessionUserFull() throws {
        let json: [String: Any] = [
            "token": "jwt-tk",
            "id": "user-1",
            "email": "user@test.com",
            "name": "Test User",
            "role": "admin",
            "profile_image_url": "https://img.com/avatar.jpg"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let user = try JSONDecoder().decode(SessionUser.self, from: data)
        #expect(user.token == "jwt-tk")
        #expect(user.id == "user-1")
        #expect(user.role == "admin")
        #expect(user.profile_image_url == "https://img.com/avatar.jpg")
    }

    @Test("SessionUser decoding with minimal fields")
    func sessionUserMinimal() throws {
        let json: [String: Any] = [
            "id": "user-min",
            "email": "min@test.com",
            "name": "Min",
            "role": "user"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let user = try JSONDecoder().decode(SessionUser.self, from: data)
        #expect(user.token == nil)
        #expect(user.profile_image_url == nil)
    }
}

// MARK: - Chat Blob Model Tests

@Suite("Chat Blob Models")
struct ChatBlobModelTests {

    @Test("ChatBlob encoding")
    func chatBlobEncoding() throws {
        let blob = ChatBlob(
            title: "Test Chat",
            history: ChatBlobHistory(messages: [:], currentId: nil),
            messages: []
        )
        let data = try JSONEncoder().encode(blob)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["title"] as? String == "Test Chat")
    }

    @Test("ChatBlobMessage encoding")
    func chatBlobMessageEncoding() throws {
        let msg = ChatBlobMessage(
            id: "msg-1",
            role: "user",
            content: "Hello",
            model: nil,
            parentId: nil,
            childrenIds: ["msg-2"],
            timestamp: 1700000000,
            images: nil,
            files: nil,
            toolCalls: nil,
            toolCallId: nil,
            statusHistory: nil
        )
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["id"] as? String == "msg-1")
        #expect(json["role"] as? String == "user")
        #expect(json["content"] as? String == "Hello")
        let children = json["childrenIds"] as? [String]
        #expect(children == ["msg-2"])
    }

    @Test("ChatBlobHistory with messages")
    func chatBlobHistory() throws {
        let msg = ChatBlobMessage(
            id: "m1", role: "user", content: "Hi", model: nil,
            parentId: nil, childrenIds: [], timestamp: nil,
            images: nil, files: nil, toolCalls: nil, toolCallId: nil, statusHistory: nil
        )
        let history = ChatBlobHistory(messages: ["m1": msg], currentId: "m1")
        let data = try JSONEncoder().encode(history)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["currentId"] as? String == "m1")
        let messages = json["messages"] as? [String: Any]
        #expect(messages?["m1"] != nil)
    }

    @Test("ChatBlobMessage with tool calls")
    func chatBlobMessageWithToolCalls() throws {
        let tc = ToolCall(
            id: "tc-1",
            type: "function",
            function: ToolCall.ToolCallComplete(name: "search", arguments: "{}"),
            status: .completed,
            result: "found"
        )
        let msg = ChatBlobMessage(
            id: "m1", role: "assistant", content: "Searching...", model: "llama3",
            parentId: nil, childrenIds: [], timestamp: nil,
            images: nil, files: nil, toolCalls: [tc], toolCallId: nil, statusHistory: nil
        )
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let toolCalls = json["toolCalls"] as? [[String: Any]]
        #expect(toolCalls?.count == 1)
    }

    @Test("ChatBlobMessage with files")
    func chatBlobMessageWithFiles() throws {
        let file = ChatFileRef(name: "doc.pdf", type: "application/pdf", size: 2048, fileId: "f-1")
        let msg = ChatBlobMessage(
            id: "m1", role: "user", content: "See attached", model: nil,
            parentId: nil, childrenIds: [], timestamp: nil,
            images: nil, files: [file], toolCalls: nil, toolCallId: nil, statusHistory: nil
        )
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let files = json["files"] as? [[String: Any]]
        #expect(files?.count == 1)
        #expect(files?[0]["name"] as? String == "doc.pdf")
    }

    @Test("ChatBlobMessage with images")
    func chatBlobMessageWithImages() throws {
        let msg = ChatBlobMessage(
            id: "m1", role: "user", content: "Look at this", model: nil,
            parentId: nil, childrenIds: [], timestamp: nil,
            images: ["data:image/png;base64,abc"], files: nil,
            toolCalls: nil, toolCallId: nil, statusHistory: nil
        )
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let images = json["images"] as? [String]
        #expect(images?.count == 1)
    }
}

// MARK: - Title Generation Model Tests

@Suite("Title Generation Models")
struct TitleGenerationModelTests {

    @Test("TitleGenerationMessage encoding")
    func messageEncoding() throws {
        let msg = TitleGenerationMessage(role: "user", content: "Hello world")
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["role"] as? String == "user")
        #expect(json["content"] as? String == "Hello world")
    }

    @Test("TitleGenerationRequest encoding")
    func requestEncoding() throws {
        let req = TitleGenerationRequest(
            model: "llama3",
            messages: [TitleGenerationMessage(role: "user", content: "Test")],
            chat_id: "chat-123"
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["model"] as? String == "llama3")
        #expect(json["chat_id"] as? String == "chat-123")
        let messages = json["messages"] as? [[String: Any]]
        #expect(messages?.count == 1)
    }

    @Test("TitleGenerationRequest with nil chat_id")
    func requestNilChatId() throws {
        let req = TitleGenerationRequest(
            model: "m",
            messages: [],
            chat_id: nil
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["chat_id"] == nil || json["chat_id"] is NSNull)
    }
}

// MARK: - Folder Model Tests

@Suite("ChatFolder")
struct ChatFolderTests {

    @Test("ChatFolder decoding")
    func decoding() throws {
        let json: [String: Any] = [
            "id": "folder-1",
            "name": "Work"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let folder = try JSONDecoder().decode(ChatFolder.self, from: data)
        #expect(folder.id == "folder-1")
        #expect(folder.name == "Work")
    }
}

// MARK: - Move Chat Request Tests

@Suite("MoveChatToFolderRequest")
struct MoveChatToFolderRequestTests {

    @Test("encoding with folder_id")
    func withFolderId() throws {
        let req = MoveChatToFolderRequest(folder_id: "folder-123")
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["folder_id"] as? String == "folder-123")
    }

    @Test("encoding with nil folder_id")
    func withNilFolderId() throws {
        let req = MoveChatToFolderRequest(folder_id: nil)
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // Default Codable skips nil optionals — folder_id should be absent from JSON
        // (unless a custom encode(to:) explicitly encodes nil as null)
        // Just verify encoding doesn't crash and produces valid JSON
        #expect(json["folder_id"] == nil || json["folder_id"] is NSNull)
    }
}
