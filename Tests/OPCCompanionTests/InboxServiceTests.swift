import XCTest
@testable import OPCCompanion

final class InboxServiceTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-inbox-test-\(UUID().uuidString)")
            .appendingPathComponent("notes.jsonl")
        tempURL = tmp
    }

    override func tearDown() {
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        super.tearDown()
    }

    func testNoteJSONRoundTrip() throws {
        let note = Note(content: "调研 langchain", source: .hotkeyText, inputMode: .text)
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(Note.self, from: data)
        XCTAssertEqual(decoded.id, note.id)
        XCTAssertEqual(decoded.content, note.content)
        XCTAssertEqual(decoded.source, .hotkeyText)
        XCTAssertEqual(decoded.status, .pending)
    }

    func testSourceRawValueMatchesPRD() {
        XCTAssertEqual(Note.Source.hotkeyVoice.rawValue, "hotkey_voice")
        XCTAssertEqual(Note.Source.hotkeyText.rawValue, "hotkey_text")
        XCTAssertEqual(Note.Source.slashInPanel.rawValue, "slash_in_panel")
        XCTAssertEqual(Note.Source.convertFromMessage.rawValue, "convert_from_message")
    }

    func testAppendAndLoadRoundTrip() {
        let service = InboxService(fileURL: tempURL)
        service.append(Note(content: "第一条", source: .hotkeyText))
        service.append(Note(content: "第二条", source: .slashInPanel))

        let loaded = service.loadAll()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map { $0.content }.sorted(), ["第一条", "第二条"])
    }

    func testConcurrentAppendDoesNotLoseRecords() {
        let service = InboxService(fileURL: tempURL)

        let expectation = self.expectation(description: "concurrent writes")
        expectation.expectedFulfillmentCount = 10

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        for i in 0..<10 {
            queue.async {
                service.append(Note(content: "并发 \(i)", source: .hotkeyText))
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 3)
        XCTAssertEqual(service.loadAll().count, 10)
    }

    func testSaveAllOverwrites() {
        let service = InboxService(fileURL: tempURL)
        service.saveAll([
            Note(content: "a", source: .hotkeyText),
            Note(content: "b", source: .hotkeyText)
        ])
        service.saveAll([Note(content: "c", source: .hotkeyText)])
        let loaded = service.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "c")
    }
}
