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

    // MARK: - MiniMax base_resp 业务错误分类

    private func assertThrows(
        _ line: String,
        _ check: (OpenAICompatibleClient.ClientError) -> Bool,
        _ message: String,
        file: StaticString = #filePath,
        line lineNum: UInt = #line
    ) {
        XCTAssertThrowsError(try OpenAICompatibleClient.parseSSELine(line), file: file, line: lineNum) { error in
            guard let e = error as? OpenAICompatibleClient.ClientError, check(e) else {
                return XCTFail("\(message)，实际：\(error)", file: file, line: lineNum)
            }
        }
    }

    func testBaseRespInvalidApiKeyMapsToUnauthorized() {
        // 2049 = invalid api key（截图主因，旧实现漏映射→落到 server）
        assertThrows(#"data: {"base_resp":{"status_code":2049,"status_msg":"invalid api key"}}"#,
                     { if case .unauthorized = $0 { return true }; return false },
                     "2049 应为 .unauthorized")
    }

    func testBaseRespAuthFailMapsToUnauthorized() {
        assertThrows(#"data: {"base_resp":{"status_code":1004,"status_msg":"login fail"}}"#,
                     { if case .unauthorized = $0 { return true }; return false },
                     "1004 应为 .unauthorized")
    }

    func testBaseRespInsufficientBalanceMapped() {
        assertThrows(#"data: {"base_resp":{"status_code":1008,"status_msg":"insufficient balance"}}"#,
                     { if case .insufficientBalance = $0 { return true }; return false },
                     "1008 应为 .insufficientBalance")
    }

    func testBaseRespTokenLimitMapsToRateLimited() {
        // 1039 = token limit（旧实现误判为 unauthorized，这里锁定为 rateLimited）
        assertThrows(#"data: {"base_resp":{"status_code":1039,"status_msg":"token limit"}}"#,
                     { if case .rateLimited = $0 { return true }; return false },
                     "1039 应为 .rateLimited")
    }

    func testBaseRespUnknownCodeFallsBackByMessageKeyword() {
        // 未知码但消息含 "api key" → 仍归类为鉴权
        assertThrows(#"data: {"base_resp":{"status_code":9999,"status_msg":"your api key is wrong"}}"#,
                     { if case .unauthorized = $0 { return true }; return false },
                     "未知码+鉴权关键词 应为 .unauthorized")
    }

    func testBaseRespSuccessCodeZeroIsNotError() throws {
        // status_code 0 = 正常（MiniMax 常在收尾 chunk 带 base_resp 0）；不应抛错，无 choices 时返回 nil
        XCTAssertNil(try OpenAICompatibleClient.parseSSELine(
            #"data: {"base_resp":{"status_code":0,"status_msg":"success"}}"#))
    }

    func testCategorize500WithApiKeyBodyIsUnauthorized() {
        guard case .unauthorized =
            OpenAICompatibleClient.ClientError.categorize(httpStatus: 500, body: "invalid api key") else {
            return XCTFail("500 + 'invalid api key' 应为 .unauthorized")
        }
    }

    func testCategorize500BalanceBodyIsInsufficientBalance() {
        guard case .insufficientBalance =
            OpenAICompatibleClient.ClientError.categorize(httpStatus: 500, body: "insufficient balance") else {
            return XCTFail("500 + 'insufficient balance' 应为 .insufficientBalance")
        }
    }
}
