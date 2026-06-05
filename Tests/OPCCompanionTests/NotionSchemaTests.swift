import XCTest
@testable import OPCCompanion

final class NotionSchemaTests: XCTestCase {
    // MARK: - schema 解析

    func testParseSchemaFindsChineseTitleColumn() throws {
        let json: [String: Any] = [
            "properties": [
                "名称": ["type": "title", "title": [:]],
                "日期": ["type": "date", "date": [:]],
                "状态": ["type": "status"]
            ]
        ]
        let schema = try NotionService.parseSchema(json)
        XCTAssertEqual(schema.titlePropertyName, "名称")
        XCTAssertEqual(schema.propertyNames, ["名称", "日期", "状态"])
    }

    func testParseSchemaThrowsWhenNoTitleColumn() {
        let json: [String: Any] = ["properties": ["日期": ["type": "date"]]]
        XCTAssertThrowsError(try NotionService.parseSchema(json))
    }

    // MARK: - 标题列名校正

    func testRemapRenamesGuessedTitleToRealColumn() {
        // AI 猜成"标题"，真实库标题列叫"名称"
        let aiProps: [String: Any] = [
            "标题": ["title": [["text": ["content": "明天3点开会"]]]],
            "日期": ["date": ["start": "2026-06-06"]]
        ]
        let fixed = ToolExecutor.remapTitleProperty(aiProps, to: "名称")
        XCTAssertNil(fixed["标题"], "猜错的标题键应被移除")
        XCTAssertNotNil(fixed["名称"], "应改名到真实标题列")
        XCTAssertNotNil(fixed["日期"], "非标题属性应原样保留")
    }

    func testRemapNoopWhenTitleAlreadyCorrect() {
        let props: [String: Any] = ["名称": ["title": [["text": ["content": "x"]]]]]
        let fixed = ToolExecutor.remapTitleProperty(props, to: "名称")
        XCTAssertNotNil(fixed["名称"])
        XCTAssertEqual(fixed.count, 1)
    }

    func testRemapNoopWhenNoTitleProperty() {
        let props: [String: Any] = ["日期": ["date": ["start": "2026-06-06"]]]
        let fixed = ToolExecutor.remapTitleProperty(props, to: "名称")
        XCTAssertNil(fixed["名称"])
        XCTAssertNotNil(fixed["日期"])
    }
}
