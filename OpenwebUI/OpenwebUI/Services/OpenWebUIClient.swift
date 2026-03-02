import Foundation

/// HTTP client for the Open WebUI API.
/// Handles auth, models, chats, and streaming chat completions.
actor OpenWebUIClient {
    let baseURL: String
    let apiKey: String

    init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.apiKey = apiKey
    }

    private var authHeader: [String: String] {
        ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"]
    }

    // MARK: - Health

    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.allHTTPHeaderFields = authHeader
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    // MARK: - Auth / User

    /// Sign in with email + password. Returns a SignInResponse with JWT token.
    /// This is a static method because we don't have a token yet.
    static func signIn(baseURL: String, email: String, password: String) async throws -> SignInResponse {
        let cleanURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(cleanURL)/api/v1/auths/signin") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = SignInRequest(email: email, password: password)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // Try to parse error detail from response
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw NSError(domain: "OpenWebUI", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: detail])
            }
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(SignInResponse.self, from: data)
    }

    func getSessionUser() async throws -> SessionUser {
        try await get("/api/v1/auths/")
    }

    // MARK: - Models

    func listModels() async throws -> [AIModel] {
        let resp: ModelListResponse = try await get("/api/models")
        return resp.data ?? []
    }

    // MARK: - Chats

    func listChats(page: Int = 1) async throws -> [ChatListItem] {
        try await get("/api/v1/chats/?page=\(page)")
    }

    func getChat(id: String) async throws -> ChatResponse {
        try await get("/api/v1/chats/\(id)")
    }

    func createChat(title: String) async throws -> ChatResponse {
        let emptyBlob = ChatBlob(
            title: title,
            history: ChatBlobHistory(messages: [:], currentId: nil),
            messages: []
        )
        let body = NewChatRequest(chat: emptyBlob)
        return try await post("/api/v1/chats/new", body: body)
    }

    /// Create a chat with full history (used when sending the first message in a new conversation).
    func createChatWithHistory(blob: ChatBlob) async throws -> ChatResponse {
        let body = NewChatRequest(chat: blob)
        return try await post("/api/v1/chats/new", body: body)
    }

    /// Update an existing chat's state on the server.
    func updateChat(id: String, blob: ChatBlob) async throws -> ChatResponse {
        let body = UpdateChatRequest(chat: blob)
        return try await post("/api/v1/chats/\(id)", body: body)
    }

    // MARK: - Title Generation

    /// Ask the server to generate a chat title from the conversation messages.
    /// Calls POST /api/v1/tasks/title/completions which uses the LLM to produce
    /// a concise title in JSON format: { "title": "..." }
    func generateTitle(model: String, messages: [TitleGenerationMessage], chatId: String?) async throws -> String? {
        let body = TitleGenerationRequest(
            model: model,
            messages: messages,
            chat_id: chatId
        )
        let response: ChatCompletionResponse = try await post("/api/v1/tasks/title/completions", body: body)

        guard let content = response.choices?.first?.message?.content else { return nil }

        // Parse JSON: { "title": "..." } — find first { and last }
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}") else {
            return nil
        }
        let jsonString = String(content[start...end])
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = parsed["title"] as? String else {
            return nil
        }
        return title
    }

    func deleteChat(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/v1/chats/\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.allHTTPHeaderFields = authHeader
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - File Upload

    /// Upload a file to the server. Returns a FileUploadResponse with the server-side file ID.
    func uploadFile(fileName: String, mimeType: String, data: Data) async throws -> FileUploadResponse {
        guard let url = URL(string: "\(baseURL)/api/v1/files/") else {
            throw URLError(.badURL)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        req.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw NSError(domain: "OpenWebUI", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: detail])
            }
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(FileUploadResponse.self, from: responseData)
    }

    // MARK: - Chat Completions (Streaming)

    /// A streaming delta: either content text or a tool call chunk.
    enum StreamDelta: Sendable {
        case content(String)
        case toolCall(ToolCallChunk)
        case done
    }

    /// Stream chat completions. Yields content deltas and tool call chunks as they arrive.
    /// Supports multimodal messages (text + images), file references, and web search.
    func streamChat(
        model: String,
        messages: [CompletionMessage],
        temperature: Double = 0.7,
        files: [CompletionFileRef]? = nil,
        webSearch: Bool = false
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        let urlString = "\(baseURL)/api/chat/completions"
        let key = apiKey

        return AsyncThrowingStream { continuation in
            Task {
                guard let url = URL(string: urlString) else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }

                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let features = webSearch ? ChatFeatures(web_search: true) : nil
                let body = ChatCompletionRequest(
                    model: model,
                    messages: messages,
                    stream: true,
                    temperature: temperature,
                    max_tokens: nil,
                    files: files,
                    features: features
                )
                req.httpBody = try? JSONEncoder().encode(body)

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        continuation.finish(throwing: URLError(.badServerResponse))
                        return
                    }

                    for try await line in bytes.lines {
                        // SSE format: "data: {...}" or "data: [DONE]"
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" {
                            break
                        }

                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data)
                        else { continue }

                        if let error = chunk.error {
                            continuation.finish(throwing: NSError(domain: "OpenWebUI", code: -1, userInfo: [NSLocalizedDescriptionKey: error]))
                            return
                        }

                        if let delta = chunk.choices?.first?.delta {
                            if let content = delta.content {
                                continuation.yield(.content(content))
                            }
                            if let toolCalls = delta.tool_calls {
                                for tc in toolCalls {
                                    continuation.yield(.toolCall(tc))
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Generic Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.allHTTPHeaderFields = authHeader
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = authHeader
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
