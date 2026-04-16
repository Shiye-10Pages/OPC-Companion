import XCTest
@testable import OPCCompanion

@MainActor
final class AppDelegateTests: XCTestCase {
    func testSharedIsAssignedDuringInitialization() {
        let delegate = AppDelegate()

        XCTAssertTrue(AppDelegate.shared === delegate)
    }

    func testMainMenuIncludesPasteCommand() throws {
        let delegate = AppDelegate()
        let menu = delegate.createMainMenu()

        XCTAssertEqual(menu.items.count, 2)

        let editMenu = try XCTUnwrap(menu.items.last?.submenu)
        XCTAssertEqual(editMenu.title, "编辑")

        let pasteItem = try XCTUnwrap(editMenu.items.first { $0.action == #selector(NSText.paste(_:)) })
        XCTAssertEqual(pasteItem.keyEquivalent, "v")
        XCTAssertEqual(pasteItem.keyEquivalentModifierMask, [.command])
    }
}
