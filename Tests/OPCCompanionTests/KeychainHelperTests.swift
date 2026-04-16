import XCTest
@testable import OPCCompanion

final class KeychainHelperTests: XCTestCase {
    private let testService = "com.shiye.opc-companion.test"
    private let testAccount = "unit-test-account"

    override func tearDown() {
        KeychainHelper.delete(account: testAccount, service: testService)
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() {
        let value = "sk-test-\(UUID().uuidString)"
        XCTAssertTrue(KeychainHelper.save(account: testAccount, value: value, service: testService))

        let loaded = KeychainHelper.load(account: testAccount, service: testService)
        XCTAssertEqual(loaded, value)
    }

    func testSaveOverwritesExisting() {
        KeychainHelper.save(account: testAccount, value: "v1", service: testService)
        KeychainHelper.save(account: testAccount, value: "v2", service: testService)
        XCTAssertEqual(KeychainHelper.load(account: testAccount, service: testService), "v2")
    }

    func testDeleteRemovesEntry() {
        KeychainHelper.save(account: testAccount, value: "to-delete", service: testService)
        XCTAssertNotNil(KeychainHelper.load(account: testAccount, service: testService))

        KeychainHelper.delete(account: testAccount, service: testService)
        XCTAssertNil(KeychainHelper.load(account: testAccount, service: testService))
    }

    func testLoadMissingReturnsNil() {
        let random = "missing-\(UUID().uuidString)"
        XCTAssertNil(KeychainHelper.load(account: random, service: testService))
    }

    func testDistinctAccountsDoNotInterfere() {
        KeychainHelper.save(account: "\(testAccount)-a", value: "A", service: testService)
        KeychainHelper.save(account: "\(testAccount)-b", value: "B", service: testService)

        XCTAssertEqual(KeychainHelper.load(account: "\(testAccount)-a", service: testService), "A")
        XCTAssertEqual(KeychainHelper.load(account: "\(testAccount)-b", service: testService), "B")

        KeychainHelper.delete(account: "\(testAccount)-a", service: testService)
        KeychainHelper.delete(account: "\(testAccount)-b", service: testService)
    }
}
