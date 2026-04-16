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

    func testPersistsAcrossInstances() {
        let cache1 = CredentialCache(fileURL: tempURL)
        cache1.loadIfNeeded()
        cache1.setMinimaxAPIKey("persist-me")

        let cache2 = CredentialCache(fileURL: tempURL)
        cache2.loadIfNeeded()
        XCTAssertEqual(cache2.getMinimaxAPIKey(), "persist-me")
    }

    func testSecretsFilePermissionsAre0600() throws {
        let cache = CredentialCache(fileURL: tempURL)
        cache.loadIfNeeded()
        cache.setMinimaxAPIKey("perm-test")

        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        XCTAssertEqual(perms & 0o777, 0o600, "secrets.json 应仅 owner 可读写（0600）")
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
