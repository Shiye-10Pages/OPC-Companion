import XCTest
@testable import OPCCompanion

final class StoaParserTests: XCTestCase {

    func testContainsRecognizedTagIncludesAliases() {
        XCTAssertTrue(StoaParser.containsRecognizedTag(in: "<facjudge><fact>事实</fact></facjudge>"))
        XCTAssertTrue(StoaParser.containsRecognizedTag(in: "<empo><opt>II | 小事 | 写一句 | Now | recommended</opt></empo>"))
        XCTAssertFalse(StoaParser.containsRecognizedTag(in: "普通文本"))
    }

    func testParsesAliasAsCanonicalTempo() {
        let segments = StoaParser.parse("""
        <empo>
        <opt>II | 低阻力任务 | 写一句话 | Now | recommended</opt>
        </empo>
        """)

        guard case .tempo(let energy, let options) = segments.first else {
            return XCTFail("expected tempo segment")
        }
        XCTAssertEqual(energy, 0)
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].roman, "II")
        XCTAssertEqual(options[0].tag, "Now")
        XCTAssertTrue(options[0].recommended)
    }

    func testParsesDichotomyLists() {
        let segments = StoaParser.parse("""
        <dichotomy>
        <in>
        - 现在写一句话
        - 关掉一个标签页
        </in>
        <out>
        - 今天决定完整课程结构
        </out>
        </dichotomy>
        """)

        guard case .dichotomy(let inn, let out) = segments.first else {
            return XCTFail("expected dichotomy segment")
        }
        XCTAssertEqual(inn, ["现在写一句话", "关掉一个标签页"])
        XCTAssertEqual(out, ["今天决定完整课程结构"])
    }

    func testMalformedTagFallsBackToText() {
        let segments = StoaParser.parse("<tempo><opt>未闭合")
        XCTAssertEqual(segments, [.text("<tempo><opt>未闭合")])
    }
}
