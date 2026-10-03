import Testing
import Foundation
@testable import Oval

/// Tests for tool catalog decoding and tool_ids / features request encoding (PR3).
@Suite("Tools and Features")
struct ToolsAndFeaturesTests {

    @Test("OWUITool decodes from the /api/v1/tools/ payload (incl. MCP servers)")
    func decodeTool() throws {
        // Exact shape captured from ai.clinger.dev GET /api/v1/tools/
        let json = """
        [{"id":"server:mcp:kagi","user_id":"server:mcp:kagi","name":"Kagi",
          "meta":{"i18n":null,"description":"Kagi Search + page extract (MCP)","manifest":{},"has_user_valves":false},
          "access_grants":[],"updated_at":1,"created_at":1,"user":null}]
        """.data(using: .utf8)!
        let tools = try JSONDecoder().decode([OWUITool].self, from: json)
        #expect(tools.count == 1)
        #expect(tools[0].id == "server:mcp:kagi")
        #expect(tools[0].name == "Kagi")
        #expect(tools[0].toolDescription == "Kagi Search + page extract (MCP)")
    }

    @Test("ChatCompletionRequest encodes tool_ids when present")
    func encodeToolIds() throws {
        let req = ChatCompletionRequest(
            model: "m", messages: [], stream: true, temperature: nil, max_tokens: nil,
            tool_ids: ["server:mcp:kagi"]
        )
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect((obj["tool_ids"] as? [String]) == ["server:mcp:kagi"])
    }

    @Test("ChatCompletionRequest omits tool_ids when nil")
    func omitToolIds() throws {
        let req = ChatCompletionRequest(model: "m", messages: [], stream: true, temperature: nil, max_tokens: nil)
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["tool_ids"] == nil)
    }

    @Test("ChatFeatures encodes only the enabled flags")
    func encodeFeatures() throws {
        let features = ChatFeatures(web_search: true, image_generation: true, memory: nil, code_interpreter: nil)
        let data = try JSONEncoder().encode(features)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["web_search"] as? Bool == true)
        #expect(obj["image_generation"] as? Bool == true)
        #expect(obj["memory"] == nil)
        #expect(obj["code_interpreter"] == nil)
    }

    @Test("ModelCapabilities decodes the memory flag")
    func decodeCapabilities() throws {
        let json = """
        {"vision":true,"web_search":true,"image_generation":true,"code_interpreter":true,"memory":true}
        """.data(using: .utf8)!
        let caps = try JSONDecoder().decode(ModelCapabilities.self, from: json)
        #expect(caps.memory == true)
        #expect(caps.image_generation == true)
    }
}
