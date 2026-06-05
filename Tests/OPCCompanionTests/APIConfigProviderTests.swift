import XCTest
@testable import OPCCompanion

final class APIConfigProviderTests: XCTestCase {
    private func endpoint(_ provider: String) -> String {
        APIConfig(provider: provider).completionEndpoint?.absoluteString ?? "nil"
    }

    // MARK: - 新增国内 provider 的端点解析

    func testMiniMaxCNUsesChatCompletionV2Path() {
        // 国内版与海外版同走 text/chatcompletion_v2，但 host 不同
        XCTAssertEqual(endpoint("minimax-cn"), "https://api.minimaxi.com/v1/text/chatcompletion_v2")
    }

    func testMiniMaxInternationalUnchanged() {
        XCTAssertEqual(endpoint("minimax"), "https://api.minimax.io/v1/text/chatcompletion_v2")
    }

    func testGLMUsesChatCompletionsUnderPaasV4() {
        // 智谱基址带 /api/paas/v4，应原样拼 /chat/completions，不能强塞 /v1
        XCTAssertEqual(endpoint("glm"), "https://open.bigmodel.cn/api/paas/v4/chat/completions")
    }

    func testKimiUsesChatCompletions() {
        XCTAssertEqual(endpoint("kimi"), "https://api.moonshot.cn/v1/chat/completions")
    }

    // MARK: - 默认模型 & 展示名

    func testDefaultModels() {
        XCTAssertEqual(APIConfig.defaultModel(for: "minimax-cn"), "MiniMax-M2.7")
        XCTAssertEqual(APIConfig.defaultModel(for: "glm"), "glm-4.6")
        XCTAssertEqual(APIConfig.defaultModel(for: "kimi"), "kimi-latest")
    }

    func testDisplayNames() {
        XCTAssertEqual(APIConfig.displayName(for: "minimax-cn"), "MiniMax (国内版)")
        XCTAssertEqual(APIConfig.displayName(for: "glm"), "智谱 GLM")
        XCTAssertEqual(APIConfig.displayName(for: "kimi"), "Kimi (Moonshot)")
    }

    func testMiniMaxPathHelperOnlyMatchesMiniMaxFamily() {
        XCTAssertTrue(APIConfig.usesMiniMaxPath("minimax"))
        XCTAssertTrue(APIConfig.usesMiniMaxPath("minimax-cn"))
        XCTAssertFalse(APIConfig.usesMiniMaxPath("glm"))
        XCTAssertFalse(APIConfig.usesMiniMaxPath("kimi"))
    }
}
