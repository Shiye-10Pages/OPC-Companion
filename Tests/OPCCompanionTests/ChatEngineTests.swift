import Foundation
import XCTest
@testable import OPCCompanion

final class ChatEngineTests: XCTestCase {
    func testDailySessionIDUsesValidUUIDFormat() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let sessionID = ChatEngine.makeSessionID(for: formatter.date(from: "2026-04-15")!)

        XCTAssertEqual(sessionID, "00000000-0000-0000-0000-202604150000")
        XCTAssertNotNil(UUID(uuidString: sessionID))
    }

    func testLegacyMiniMaxURLIsNormalized() {
        let config = APIConfig(provider: "minimax", apiKey: "test", baseURL: APIConfig.legacyMiniMaxBaseURL)

        XCTAssertEqual(config.normalizedBaseURL, APIConfig.miniMaxInternationalBaseURL)
    }

    func testCompatibleClientUsesConfiguredDefaultModel() {
        XCTAssertEqual(OpenAICompatibleClient.defaultModel, APIConfig.miniMaxDefaultModel)
        XCTAssertEqual(APIConfig.miniMaxDefaultModel, "MiniMax-M2.7")
    }

    func testProviderDefaultsResolveExpectedEndpointsAndModels() {
        let cases = [
            ("minimax", "https://api.minimax.io/v1/text/chatcompletion_v2", "MiniMax-M2.7"),
            ("deepseek", "https://api.deepseek.com/chat/completions", "deepseek-v4-flash"),
            ("qwen", "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", "qwen-plus"),
            ("openai", "https://api.openai.com/v1/chat/completions", "gpt-5.4-mini"),
            ("anthropic", "https://api.anthropic.com/v1/chat/completions", "claude-sonnet-4-6"),
            ("siliconflow", "https://api.siliconflow.cn/v1/chat/completions", "deepseek-ai/DeepSeek-V3.2")
        ]

        for (provider, endpoint, model) in cases {
            let config = APIConfig(provider: provider)
            XCTAssertEqual(config.completionEndpoint?.absoluteString, endpoint)
            XCTAssertEqual(config.resolvedModel, model)
        }
    }

    func testCustomProviderAcceptsFullCompletionEndpoint() {
        let config = APIConfig(provider: "custom", baseURL: "https://example.com/v1/chat/completions", model: "custom-model")

        XCTAssertEqual(config.completionEndpoint?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(config.resolvedModel, "custom-model")
    }
}
