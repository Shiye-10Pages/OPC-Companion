import XCTest
@testable import OPCCompanion

final class CredentialCacheTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-secrets-test-\(UUID().uuidString)")
            .appendingPathComponent("secrets.json")
    }

    override func tearDown() {
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        super.tearDown()
    }

    func testSetAndGetRoundTrip() {
        let cache = CredentialCache(fileURL: tempURL)
        cache.loadIfNeeded()

        cache.setMinimaxAPIKey("sk-test-123")
        cache.setNotionToken("notion-secret")

        XCTAssertEqual(cache.getMinimaxAPIKey(), "sk-test-123")
        XCTAssertEqual(cache.getNotionToken(), "notion-secret")
    }

    func testNoPlaintextFileAfterSet() {
        let cache = CredentialCache(fileURL: tempURL)
        cache.loadIfNeeded()
        cache.setMinimaxAPIKey("persist-me")
        cache.setNotionToken("tok")
        // 安全不变量：凭证绝不明文落盘（旧 secrets.json 路径已废弃，改用 Keychain）
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                       "凭证绝不能明文写入 secrets.json")
    }

    func testLegacyFileMigratedAndDeleted() throws {
        // 历史明文 secrets.json 存在 → loadIfNeeded 迁移进缓存并删除明文文件
        let dir = tempURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = ["minimax_api_key": "legacy-key", "notion_token": "legacy-tok"]
        try JSONSerialization.data(withJSONObject: payload).write(to: tempURL)

        let cache = CredentialCache(fileURL: tempURL)
        cache.loadIfNeeded()
        XCTAssertEqual(cache.getMinimaxAPIKey(), "legacy-key")
        XCTAssertEqual(cache.getNotionToken(), "legacy-tok")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                       "迁移后历史明文 secrets.json 必须删除")
    }

    func testEmptyOnFreshLoad() {
        let cache = CredentialCache(fileURL: tempURL)
        cache.loadIfNeeded()
        XCTAssertEqual(cache.getMinimaxAPIKey(), "")
        XCTAssertEqual(cache.getNotionToken(), "")
    }

    func testReadsExistingFile() throws {
        // 预写入文件
        let dir = tempURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload: [String: String] = [
            "minimax_api_key": "preset-key",
            "notion_token": "preset-token"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: tempURL)

        let cache = CredentialCache(fileURL: tempURL)
        cache.loadIfNeeded()
        XCTAssertEqual(cache.getMinimaxAPIKey(), "preset-key")
        XCTAssertEqual(cache.getNotionToken(), "preset-token")
    }
}
