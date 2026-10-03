import Testing
import Foundation
@testable import Oval

/// Tests for the OpenAI Responses API streaming reducer (`AppState.ResponsesStreamState`).
/// Payload shapes mirror events captured live from an Open WebUI 0.11 instance.
@Suite("ResponsesStreamState")
struct ResponsesStreamStateTests {

    typealias State = AppState.ResponsesStreamState

    @Test("role-only chunk makes no change")
    func roleChunkNoop() {
        var s = State()
        let changed = s.apply(event: ["choices": [["delta": ["role": "assistant"]]]] as [String: Any])
        #expect(changed == false)
        #expect(s.render() == "")
    }

    @Test("reasoning deltas render as an unclosed, animated block; answer closes it")
    func reasoningThenAnswer() {
        var s = State()
        s.apply(event: ["type": "response.reasoning_text.delta", "delta": "Think"] as [String: Any])
        s.apply(event: ["type": "response.reasoning_text.delta", "delta": "ing"] as [String: Any])

        // While reasoning streams, the details block is left unclosed (renders "Thinking…").
        let mid = s.render()
        #expect(mid.contains("<details type=\"reasoning\">"))
        #expect(!mid.contains("</details>"))
        #expect(mid.contains("Thinking"))
        #expect(s.answer.isEmpty)

        // The first answer token closes the reasoning block.
        s.apply(event: ["type": "response.output_text.delta", "delta": "Blue."] as [String: Any])
        #expect(s.reasoningClosed)
        let done = s.render()
        #expect(done.contains("done=\"true\""))
        #expect(done.contains("</details>"))
        #expect(done.hasSuffix("Blue."))
    }

    @Test("output_item.done carries reasoning duration")
    func reasoningDuration() {
        var s = State()
        s.apply(event: ["type": "response.reasoning_text.delta", "delta": "x"] as [String: Any])
        s.apply(event: ["type": "response.output_item.done",
                        "item": ["type": "reasoning", "duration": 3]] as [String: Any])
        #expect(s.reasoningClosed)
        #expect(s.reasoningDuration == 3)
        #expect(s.render().contains("duration=\"3\""))
    }

    @Test("classic chunk reasoning_content + content folds into reasoning then answer")
    func classicChunkReasoningContent() {
        var s = State()
        s.apply(event: ["choices": [["delta": ["reasoning_content": "hmm"]]]] as [String: Any])
        s.apply(event: ["choices": [["delta": ["content": "Hi"]]]] as [String: Any])
        #expect(s.reasoning == "hmm")
        #expect(s.answer == "Hi")
        #expect(s.reasoningClosed)
    }

    @Test("finalize from the authoritative output array (reasoning + message)")
    func finalizeSimple() {
        let output: [[String: Any]] = [
            ["type": "reasoning", "duration": 1,
             "content": [["type": "output_text", "text": "Because chlorophyll."]]],
            ["type": "message", "role": "assistant",
             "content": [["type": "output_text", "text": "Grass is green because chlorophyll reflects green light."]]],
        ]
        var s = State()
        let ok = s.finalize(output: output)
        #expect(ok)
        #expect(s.answer == "Grass is green because chlorophyll reflects green light.")
        #expect(s.reasoning == "Because chlorophyll.")
        #expect(s.reasoningDuration == 1)
        let r = s.render()
        #expect(r.contains("duration=\"1\""))
        #expect(r.contains("Grass is green"))
    }

    @Test("finalize over a multi-round research output drops whitespace preambles and tool items")
    func finalizeResearch() {
        let output: [[String: Any]] = [
            ["type": "reasoning", "content": [["type": "output_text", "text": "r1"]]],
            ["type": "message", "content": [["type": "output_text", "text": "\n\n"]]],
            ["type": "function_call", "call_id": "c1", "name": "kagi_kagi_search_fetch", "arguments": "{}"],
            ["type": "function_call_output", "call_id": "c1",
             "output": [["type": "input_text", "text": "search results"]]],
            ["type": "reasoning", "content": [["type": "output_text", "text": "r2"]]],
            ["type": "message", "content": [["type": "output_text", "text": "Tokyo's population is ~14M. Source: https://example.com"]]],
        ]
        var s = State()
        let ok = s.finalize(output: output)
        #expect(ok)
        #expect(s.answer == "Tokyo's population is ~14M. Source: https://example.com")
        #expect(s.reasoning == "r1\nr2")
    }

    @Test("finalize returns false for empty output")
    func finalizeEmpty() {
        var s = State()
        let ok = s.finalize(output: [])
        #expect(ok == false)
    }

    @Test("tool call events render as a tool_calls block with args and result")
    func toolCallConsole() {
        var s = State()
        s.apply(event: ["type": "response.output_item.added",
                        "item": ["type": "function_call", "call_id": "c1", "name": "kagi_search", "arguments": ""]] as [String: Any])
        s.apply(event: ["type": "response.function_call_arguments.delta",
                        "item_id": "c1", "delta": "{\"query\":\"tokyo\"}"] as [String: Any])
        s.apply(event: ["type": "response.output_item.done",
                        "item": ["type": "function_call", "call_id": "c1", "name": "kagi_search", "arguments": "{\"query\":\"tokyo\"}"]] as [String: Any])
        s.apply(event: ["type": "response.output_item.done",
                        "item": ["type": "function_call_output", "call_id": "c1", "output": [["type": "input_text", "text": "pop 14M"]]]] as [String: Any])
        let r = s.render()
        #expect(r.contains("type=\"tool_calls\""))
        #expect(r.contains("name=\"kagi_search\""))
        #expect(r.contains("tokyo"))
        #expect(r.contains("pop 14M"))
        #expect(r.contains("done=\"true\""))
    }

    @Test("rendered tool_calls block round-trips through parseToolCallDetails")
    func toolCallRoundTrip() {
        var s = State()
        s.apply(event: ["type": "response.output_item.added",
                        "item": ["type": "function_call", "call_id": "c1", "name": "kagi_search", "arguments": "{\"query\":\"tokyo\"}"]] as [String: Any])
        s.apply(event: ["type": "response.output_item.done",
                        "item": ["type": "function_call_output", "call_id": "c1", "output": "result text"]] as [String: Any])
        let parsed = AppState.parseToolCallDetails(from: s.render())
        #expect(parsed.count == 1)
        #expect(parsed.first?.function.name == "kagi_search")
        #expect(parsed.first?.function.arguments.contains("tokyo") == true)
        #expect(parsed.first?.result == "result text")
    }
}
