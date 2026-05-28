import XCTest
@testable import OPCCompanion

final class ThinkingParserTests: XCTestCase {

    func testParsesThinkingAndMainContent() {
        let parsed = ThinkingParser.parse("""
        <think>
        内部推理
        </think>

        <module>M4 · 顺势而为</module>
        """)

        XCTAssertEqual(parsed.thinking, "内部推理")
        XCTAssertEqual(parsed.main, "<module>M4 · 顺势而为</module>")
    }

    func testParsesThinkingWithAttributesAndDifferentCase() {
        let parsed = ThinkingParser.parse("""
        <THINK type="hidden">不要展示</THINK>
        正文
        """)

        XCTAssertEqual(parsed.thinking, "不要展示")
        XCTAssertEqual(parsed.main, "正文")
    }

    func testStripsLiteralEscapedThinkingCloseTag() {
        let parsed = ThinkingParser.parse(#"""
        <think>内部推理<\/think>
        正文
        """#)

        XCTAssertEqual(parsed.thinking, "内部推理")
        XCTAssertEqual(parsed.main, "正文")
    }

    func testStripsStrayThinkingTagsFromMainContent() {
        let parsed = ThinkingParser.parse("""
        <think>
        内部推理
        </think>
        </think>
        正文
        """)

        XCTAssertEqual(parsed.thinking, "内部推理")
        XCTAssertEqual(parsed.main, "正文")
    }

    func testStoaDisplayParserDoesNotSplitOnModuleMentionInsideThinking() {
        let parsed = StoaParser.parseDisplayContent("""
        <think>
        I should give a brief response.
        1. Start with <module> tag
        2. Short Socratic line in Chinese
        3. Exactly ONE structured block - tempo
        </think>

        <module>M4 · 顺势而为</module>
        既然切来切去是惯性，如此，则需要一个物理断点。
        <tempo>
        <opt>II | 快速收割 | 关掉非正经标签，只补充一行主线内容就停 | Now | recommended</opt>
        </tempo>
        """)

        XCTAssertEqual(parsed.thinking?.contains("Start with <module> tag"), true)
        XCTAssertFalse(parsed.main.contains("Short Socratic line"))
        XCTAssertTrue(parsed.main.hasPrefix("<module>M4 · 顺势而为</module>"))
        XCTAssertTrue(parsed.main.contains("<tempo>"))
    }
}
