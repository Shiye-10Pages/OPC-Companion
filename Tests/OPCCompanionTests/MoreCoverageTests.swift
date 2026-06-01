import XCTest
@testable import OPCCompanion

@MainActor
final class ConvertMessageHidesAdjacentReplyTests: XCTestCase {
    func testConvertingUserMessageAlsoHidesNextAssistantReply() {
        let state = AppState()
        state.messages.removeAll()
        state.notes.removeAll()

        let userMsg = Message(role: .user, content: "调研 langchain")
        let aiReply = Message(role: .assistant, content: "好的，langchain 是…")
        state.appendMessage(userMsg)
        state.appendMessage(aiReply)

        state.convertMessageToNote(userMsg)

        let storedUser = state.messages.first { $0.id == userMsg.id }
        let storedAI = state.messages.first { $0.id == aiReply.id }
        XCTAssertEqual(storedUser?.hidden, true)
        XCTAssertEqual(storedAI?.hidden, true, "user 转随手记时紧邻的 assistant 也应隐藏")
    }

    func testConvertingAssistantDoesNotAffectAdjacent() {
        let state = AppState()
        state.messages.removeAll()
        state.notes.removeAll()

        let userMsg = Message(role: .user, content: "你好")
        let aiReply = Message(role: .assistant, content: "你好！")
        state.appendMessage(userMsg)
        state.appendMessage(aiReply)

        state.convertMessageToNote(aiReply)

        XCTAssertEqual(state.messages.first { $0.id == aiReply.id }?.hidden, true)
        XCTAssertEqual(state.messages.first { $0.id == userMsg.id }?.hidden, false, "转 assistant 不应连带隐藏前面的 user")
    }
}

final class CompatibleAPIErrorCategorizeTests: XCTestCase {
    func testCategorize401() {
        if case .unauthorized = OpenAICompatibleClient.ClientError.categorize(httpStatus: 401, body: "bad") {
            // ok
        } else { XCTFail("401 应归类为 unauthorized") }
    }

    func testCategorize429() {
        if case .rateLimited = OpenAICompatibleClient.ClientError.categorize(httpStatus: 429, body: "") {
        } else { XCTFail("429 应归类为 rateLimited") }
    }

    func testCategorize500IsRetriable() {
        let err = OpenAICompatibleClient.ClientError.categorize(httpStatus: 503, body: "down")
        XCTAssertTrue(err.isRetriable, "5xx 应可重试")
    }

    func testCategorize400IsNotRetriable() {
        let err = OpenAICompatibleClient.ClientError.categorize(httpStatus: 400, body: "bad input")
        XCTAssertFalse(err.isRetriable, "400 不应重试")
    }

    func testNetworkErrorIsRetriable() {
        let underlying = NSError(domain: "test", code: -1)
        let err = OpenAICompatibleClient.ClientError.network(underlying: underlying)
        XCTAssertTrue(err.isRetriable)
    }
}

final class NotionErrorCategorizeTests: XCTestCase {
    func testCategorize404() {
        if case .notFound = NotionError.categorize(httpStatus: 404, message: "no page") {
        } else { XCTFail("404 应归类为 notFound") }
    }

    func testCategorize429() {
        if case .rateLimited = NotionError.categorize(httpStatus: 429, message: "") {
        } else { XCTFail("429 应归类为 rateLimited") }
    }
}

@MainActor
final class ToolExecutorBadInputTests: XCTestCase {
    func testStartTimerWithoutMinutesReturnsError() async {
        let call = WireToolCall(
            id: "x",
            function: WireFunctionCall(name: "start_timer", arguments: #"{"task":"写稿"}"#)
        )
        let result = await ToolExecutor.execute(call)
        XCTAssertTrue(result.contains("\"status\":\"error\""), "缺 minutes 应返回错误")
    }

    func testStartTimerWithBrokenJSONReturnsError() async {
        let call = WireToolCall(
            id: "x",
            function: WireFunctionCall(name: "start_timer", arguments: "{not json")
        )
        let result = await ToolExecutor.execute(call)
        XCTAssertTrue(result.contains("\"status\":\"error\""))
    }

    func testQueryNotionWithoutDatabaseConfigReturnsError() async {
        let state = AppState.shared
        state.config.notionDatabaseIds.calendar = nil
        let call = WireToolCall(
            id: "x",
            function: WireFunctionCall(name: "query_notion_database", arguments: #"{"database_key":"calendar"}"#)
        )
        let result = await ToolExecutor.execute(call)
        XCTAssertTrue(result.contains("\"status\":\"error\""))
        XCTAssertTrue(result.contains("数据库未配置"))
    }
}

final class CredentialMigrationFromKeychainTests: XCTestCase {
    private var tempURL: URL!
    private let testService = "com.shiye.opc-companion.migration-test"

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-migration-\(UUID().uuidString)")
            .appendingPathComponent("secrets.json")
    }

    override func tearDown() {
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        KeychainHelper.delete(account: KeychainHelper.Account.minimaxAPIKey)
        KeychainHelper.delete(account: KeychainHelper.Account.notionToken)
        super.tearDown()
    }

    func testLoadIfNeededReadsExistingFileWithoutTouchingKeychain() throws {
        // 文件已存在 → 直接读，不应 fallback Keychain
        let dir = tempURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = ["minimax_api_key": "from-file"]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: tempURL)

        // 同时往 Keychain 放一个值，验证不会被读
        KeychainHelper.save(account: KeychainHelper.Account.minimaxAPIKey, value: "from-keychain")

        let cache = CredentialCache(fileURL: tempURL)
        cache.loadIfNeeded()
        XCTAssertEqual(cache.getMinimaxAPIKey(), "from-file")
    }
}
