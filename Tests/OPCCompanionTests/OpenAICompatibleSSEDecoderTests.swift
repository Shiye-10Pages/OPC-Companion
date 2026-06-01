import XCTest
@testable import OPCCompanion

final class OpenAICompatibleSSEDecoderTests: XCTestCase {
    func testEmptyLineReturnsNil() throws {
        XCTAssertNil(try OpenAICompatibleClient.parseSSELine(""))
        XCTAssertNil(try OpenAICompatibleClient.parseSSELine("   "))
    }

    func testNonDataLineReturnsNil() throws {
        XCTAssertNil(try OpenAICompatibleClient.parseSSELine(": keep-alive"))
        XCTAssertNil(try OpenAICompatibleClient.parseSSELine("event: message"))
    }

    func testDoneMarkerIsDetected() {
        XCTAssertTrue(OpenAICompatibleClient.isDoneMarker("data: [DONE]"))
        XCTAssertTrue(OpenAICompatibleClient.isDoneMarker("data:[DONE]"))
        XCTAssertFalse(OpenAICompatibleClient.isDoneMarker("data: {\"foo\":1}"))
    }

    func testContentDeltaExtracted() throws {
        let line = #"data: {"choices":[{"delta":{"content":"你好"}}]}"#
        let chunk = try XCTUnwrap(OpenAICompatibleClient.parseSSELine(line))
        XCTAssertEqual(chunk.contentDelta, "你好")
        XCTAssertTrue(chunk.toolCallDeltas.isEmpty)
        XCTAssertNil(chunk.finishReason)
    }

    func testFinishReasonExtracted() throws {
        let line = #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        let chunk = try XCTUnwrap(OpenAICompatibleClient.parseSSELine(line))
        XCTAssertEqual(chunk.finishReason, "stop")
    }

    func testToolCallDeltaExtracted() throws {
        let line = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"start_timer","arguments":"{\"task\""}}]}}]}"#
        let chunk = try XCTUnwrap(OpenAICompatibleClient.parseSSELine(line))
        XCTAssertEqual(chunk.toolCallDeltas.count, 1)
        let delta = chunk.toolCallDeltas[0]
        XCTAssertEqual(delta.index, 0)
        XCTAssertEqual(delta.id, "call_1")
        XCTAssertEqual(delta.name, "start_timer")
        XCTAssertEqual(delta.argumentsFragment, "{\"task\"")
    }

    func testToolCallBufferAccumulatesArguments() {
        let buffer = ToolCallBuffer()
        buffer.apply(delta: ToolCallDelta(index: 0, id: "call_1", name: "start_timer", argumentsFragment: #"{"task":"#))
        buffer.apply(delta: ToolCallDelta(index: 0, id: nil, name: nil, argumentsFragment: #""写稿","#))
        buffer.apply(delta: ToolCallDelta(index: 0, id: nil, name: nil, argumentsFragment: #""minutes":25}"#))

        let calls = buffer.finalized()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].id, "call_1")
        XCTAssertEqual(calls[0].function.name, "start_timer")
        XCTAssertEqual(calls[0].function.arguments, #"{"task":"写稿","minutes":25}"#)
    }

    func testToolCallBufferHandlesMultipleCalls() {
        let buffer = ToolCallBuffer()
        buffer.apply(delta: ToolCallDelta(index: 0, id: "a", name: "tool_a", argumentsFragment: "{}"))
        buffer.apply(delta: ToolCallDelta(index: 1, id: "b", name: "tool_b", argumentsFragment: "{}"))

        let calls = buffer.finalized()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].function.name, "tool_a")
        XCTAssertEqual(calls[1].function.name, "tool_b")
    }

    func testToolCallBufferIgnoresIncompleteSlot() {
        let buffer = ToolCallBuffer()
        // 只给 arguments，没有 id/name
        buffer.apply(delta: ToolCallDelta(index: 0, id: nil, name: nil, argumentsFragment: "{}"))
        XCTAssertTrue(buffer.finalized().isEmpty)
    }
}
