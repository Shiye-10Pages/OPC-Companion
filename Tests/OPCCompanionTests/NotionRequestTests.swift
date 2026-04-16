import XCTest
@testable import OPCCompanion

final class NotionRequestTests: XCTestCase {
    func testMakeRequestSetsRequiredHeaders() throws {
        let request = try NotionService.makeRequest(
            path: "/search",
            method: "POST",
            bodyData: nil,
            token: "secret_xxx"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret_xxx")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), NotionService.apiVersion)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testMakeRequestUrlComposesAgainstBaseURL() throws {
        let request = try NotionService.makeRequest(
            path: "/databases/abc/query",
            method: "POST",
            bodyData: nil,
            token: "t"
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.notion.com/v1/databases/abc/query")
    }

    func testMakeRequestAttachesBodyData() throws {
        let body = try JSONSerialization.data(withJSONObject: ["foo": "bar"], options: [])
        let request = try NotionService.makeRequest(
            path: "/pages",
            method: "POST",
            bodyData: body,
            token: "t"
        )
        XCTAssertEqual(request.httpBody, body)
    }

    func testGetRequestOmitsBody() throws {
        let body = try JSONSerialization.data(withJSONObject: ["foo": "bar"], options: [])
        let request = try NotionService.makeRequest(
            path: "/pages/abc",
            method: "GET",
            bodyData: body,
            token: "t"
        )
        XCTAssertNil(request.httpBody)
    }

    func testNotionDatabaseIdsLookup() {
        let ids = NotionDatabaseIds(calendar: "cal-1", todos: "todo-1", inbox: "in-1")
        XCTAssertEqual(ids.id(for: "calendar"), "cal-1")
        XCTAssertEqual(ids.id(for: "todos"), "todo-1")
        XCTAssertEqual(ids.id(for: "inbox"), "in-1")
        XCTAssertNil(ids.id(for: "unknown"))
    }
}
