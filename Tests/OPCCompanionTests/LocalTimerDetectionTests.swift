import XCTest
@testable import OPCCompanion

final class LocalTimerDetectionTests: XCTestCase {
    func testChineseCommaPattern() {
        let r = ChatEngine.detectLocalTimer(in: "开始写代码，25 分钟")
        XCTAssertEqual(r?.task, "写代码")
        XCTAssertEqual(r?.minutes, 25)
    }

    func testSpaceOnlyPattern() {
        let r = ChatEngine.detectLocalTimer(in: "开始 回复邮件 15 分钟")
        XCTAssertEqual(r?.task, "回复邮件")
        XCTAssertEqual(r?.minutes, 15)
    }

    func testNoSpaceBetweenNumberAndSuffix() {
        let r = ChatEngine.detectLocalTimer(in: "开始写周报30分钟")
        XCTAssertEqual(r?.task, "写周报")
        XCTAssertEqual(r?.minutes, 30)
    }

    func testUnrelatedSentenceReturnsNil() {
        XCTAssertNil(ChatEngine.detectLocalTimer(in: "今天天气不错"))
        XCTAssertNil(ChatEngine.detectLocalTimer(in: "开始吧"))
    }

    func testRejectsOutOfRangeMinutes() {
        XCTAssertNil(ChatEngine.detectLocalTimer(in: "开始摸鱼 0 分钟"))
    }

    func testRejectsEmptyTaskName() {
        XCTAssertNil(ChatEngine.detectLocalTimer(in: "开始 25 分钟"))
    }
}
