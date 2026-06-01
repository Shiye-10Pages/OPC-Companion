import XCTest
@testable import OPCCompanion

final class WeeklyArchiveServiceTests: XCTestCase {
    func testPreviousISOWeekCrossesYearWithoutWeekZero() throws {
        let date = try XCTUnwrap(makeDate("2027-01-04"))

        let previous = try XCTUnwrap(WeeklyArchiveService.previousISOWeek(before: date))

        XCTAssertEqual(previous.year, 2026)
        XCTAssertEqual(previous.week, 53)
    }

    private func makeDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
