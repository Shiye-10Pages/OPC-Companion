import XCTest
@testable import OPCCompanion

final class LogRedactorTests: XCTestCase {
    func testRedactsBearerToken() {
        let out = LogRedactor.redact("Authorization: Bearer sk-abc123DEF456ghi789")
        XCTAssertFalse(out.contains("abc123DEF456ghi789"))
        XCTAssertTrue(out.contains("***"))
    }

    func testRedactsHomePathUsername() {
        let out = LogRedactor.redact("wrote /Users/zhangwei/.opc-companion/session.txt")
        XCTAssertTrue(out.contains("/Users/USER/"))
        XCTAssertFalse(out.contains("zhangwei"))
    }

    func testRedactsEmailAndPhone() {
        let out = LogRedactor.redact("contact a.b@example.com or 13912345678 please")
        XCTAssertFalse(out.contains("a.b@example.com"))
        XCTAssertFalse(out.contains("13912345678"))
    }

    func testRedactsNotionToken() {
        let out = LogRedactor.redact("token=secret_ABCDEFGH12345678abcdEFGH")
        XCTAssertFalse(out.contains("ABCDEFGH12345678abcdEFGH"))
    }

    func testKeepsNonSensitiveDiagnostics() {
        // HTTP 码、host、base_resp 码、错误类型等无隐私信息应原样保留
        let input = "http 200 host=api.minimax.io base_resp=2049 -> unauthorized"
        XCTAssertEqual(LogRedactor.redact(input), input)
    }
}
