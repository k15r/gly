import XCTest
@testable import GlyCore

/// task-properties T3: the date words of the due date popover (shared with quick capture).
final class DateWordsTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }()
    let today = LocalDay("2026-10-28")!      // a Wednesday

    func parse(_ s: String) -> String? {
        DateWords.parse(s, today: today, calendar: cal).map { $0.day.description + ($0.time.map { " " + $0 } ?? "") }
    }

    func testWeekdays() {
        XCTAssertEqual(parse("fri"), "2026-10-30")
        XCTAssertEqual(parse("Friday"), "2026-10-30")
        XCTAssertEqual(parse("wed"), "2026-11-04", "today's weekday = a week ahead")
    }

    func testTodayTomorrowAndISO() {
        XCTAssertEqual(parse("today"), "2026-10-28")
        XCTAssertEqual(parse("tomorrow"), "2026-10-29")
        XCTAssertEqual(parse("2026-12-24"), "2026-12-24")
    }

    func testDayMonth() {
        XCTAssertEqual(parse("3 nov"), "2026-11-03")
        XCTAssertEqual(parse("3. November"), "2026-11-03")
        XCTAssertEqual(parse("1 jan"), "2027-01-01", "past this year → next year")
    }

    func testWithTime() {
        XCTAssertEqual(parse("fri 14:00"), "2026-10-30 14:00")
        XCTAssertEqual(parse("tomorrow 9:30"), "2026-10-29 09:30")
        XCTAssertEqual(parse("3 nov 08:15"), "2026-11-03 08:15")
    }

    func testNonsense() {
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("soon"))
        XCTAssertNil(parse("fri 25:00"))
        XCTAssertNil(parse("call fri"), "more than a date")
        XCTAssertNil(parse("14:00"), "a time alone is no date")
    }
}
