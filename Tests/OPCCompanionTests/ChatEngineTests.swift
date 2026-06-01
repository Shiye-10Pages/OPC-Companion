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

    func testMiniMaxClientUsesConfiguredDefaultModel() {
        XCTAssertEqual(MiniMaxClient.defaultModel, APIConfig.miniMaxDefaultModel)
        XCTAssertEqual(APIConfig.miniMaxDefaultModel, "MiniMax-M2.7")
    }
}
