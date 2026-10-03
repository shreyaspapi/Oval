import Testing
import Foundation
@testable import Oval

/// Tests for sub-agent ("research agent") result message metadata decoding (PR4).
@Suite("Subagent message meta")
struct SubagentMetaTests {

    @Test("ChatMessage decodes injected sub-agent meta")
    func decodeSubagentMeta() throws {
        let json = """
        {"id":"m1","role":"user",
         "content":"[ASYNC SUBAGENT COMPLETE - deleg_abc123]\\nSubagent chat: c9\\nStatus: completed\\n--- RESULT ---\\nTokyo has about 14 million people.",
         "meta":{"internal":true,"type":"subagent","delegation_id":"deleg_abc123","subagent_chat_id":"c9"}}
        """.data(using: .utf8)!
        let msg = try JSONDecoder().decode(ChatMessage.self, from: json)
        #expect(msg.meta?.isSubagentResult == true)
        #expect(msg.meta?.delegationId == "deleg_abc123")
        #expect(msg.meta?.subagentChatId == "c9")
    }

    @Test("a normal message has no sub-agent meta")
    func normalMessageNoMeta() throws {
        let json = """
        {"id":"m2","role":"assistant","content":"hello"}
        """.data(using: .utf8)!
        let msg = try JSONDecoder().decode(ChatMessage.self, from: json)
        #expect(msg.meta == nil)
    }

    @Test("internal flag without subagent type is not a sub-agent result")
    func internalButNotSubagent() throws {
        let json = """
        {"id":"m3","role":"user","content":"x","meta":{"internal":true,"type":"timer"}}
        """.data(using: .utf8)!
        let msg = try JSONDecoder().decode(ChatMessage.self, from: json)
        #expect(msg.meta?.isSubagentResult == false)
    }
}
