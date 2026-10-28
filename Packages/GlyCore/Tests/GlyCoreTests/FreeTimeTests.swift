import Foundation
import XCTest
@testable import GlyCore

final class FreeTimeTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }()
    let hours = WorkingHours()  // 09–17

    func at(_ d: String, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: LocalDay(d)!.interval(in: cal).start)!
    }
    func free(_ from: Date, _ to: Date, _ busy: [(DateInterval, BlockingWeight)], hours: WorkingHours? = nil) -> Double {
        FreeTime.minutes(from: from, to: to, busy: busy.map { (interval: $0.0, weight: $0.1) }, hours: hours ?? self.hours, calendar: cal)
    }
    func iv(_ a: Date, _ b: Date) -> DateInterval { DateInterval(start: a, end: b) }

    func testFullFreeDay() {
        XCTAssertEqual(free(at("2026-10-27", 0), at("2026-10-28", 0), []), 480)
    }

    func testOverlappingMeetingsCountOnce() {
        let d = "2026-10-27"
        let busy: [(DateInterval, BlockingWeight)] = [(iv(at(d, 10), at(d, 11)), .blocks), (iv(at(d, 10, 30), at(d, 11, 30)), .blocks)]
        XCTAssertEqual(free(at(d, 0), at("2026-10-28", 0), busy), 480 - 90)
    }

    func testTentativeCountsHalfAndNotTwiceUnderABlock() {
        let d = "2026-10-27"
        XCTAssertEqual(free(at(d, 0), at("2026-10-28", 0), [(iv(at(d, 13), at(d, 14)), .maybe)]), 480 - 30)
        let both: [(DateInterval, BlockingWeight)] = [(iv(at(d, 13), at(d, 14)), .blocks), (iv(at(d, 13, 30), at(d, 14, 30)), .maybe)]
        XCTAssertEqual(free(at(d, 0), at("2026-10-28", 0), both), 480 - 60 - 15)
    }

    func testLaterToday() {
        let d = "2026-10-27"
        XCTAssertEqual(free(at(d, 15), at("2026-10-28", 0), []), 120)
    }

    func testNowInsideAMeeting() {
        let d = "2026-10-27"
        XCTAssertEqual(free(at(d, 10, 30), at(d, 17), [(iv(at(d, 10), at(d, 11)), .blocks)]), 390 - 30)
    }

    func testChangeWorkingHours() {
        XCTAssertEqual(free(at("2026-10-27", 0), at("2026-10-28", 0), [], hours: WorkingHours(startMinute: 8 * 60, endMinute: 16 * 60)), 480)
        XCTAssertEqual(free(at("2026-10-27", 0), at("2026-10-27", 12), [], hours: WorkingHours(startMinute: 8 * 60, endMinute: 16 * 60)), 240)
    }

    func testOutsideWorkingHoursIsIgnored() {
        let d = "2026-10-27"
        XCTAssertEqual(free(at(d, 0), at("2026-10-28", 0), [(iv(at(d, 18), at(d, 20)), .blocks)]), 480)
    }

    func testAllDayBlock() {
        XCTAssertEqual(free(at("2026-10-27", 0), at("2026-10-29", 0), [(iv(at("2026-10-27", 0), at("2026-10-28", 0)), .blocks)]), 480)
    }

    func testDSTDay() {
        // 25 Oct 2026: clocks go back in Europe/Berlin; the working window is still 09–17 wall clock = 8 h.
        // DST changes fall on Sundays, so this counts every day as a working day.
        let everyDay = WorkingHours(workdays: Set(1...7))
        XCTAssertEqual(free(at("2026-10-25", 0), at("2026-10-26", 0), [], hours: everyDay), 480)
        XCTAssertEqual(free(at("2026-03-29", 0), at("2026-03-30", 0), [], hours: everyDay), 480)
    }

    func testWeekendHasNoFreeTime() {
        // specs/daily-planning "Weekend": Fri 30 Oct to Mon 2 Nov counts Friday and Monday only.
        XCTAssertEqual(free(at("2026-10-31", 0), at("2026-11-02", 0), []), 0, "Saturday and Sunday")
        XCTAssertEqual(free(at("2026-10-30", 0), at("2026-11-03", 0), []), 960)
    }

    func testChangeWorkingDays() {
        // specs/daily-planning "Change working days": Saturday counts once it's a working day.
        let withSaturday = WorkingHours(workdays: WorkingHours.mondayToFriday.union([7]))
        XCTAssertEqual(free(at("2026-10-31", 0), at("2026-11-01", 0), [], hours: withSaturday), 480)
        XCTAssertEqual(free(at("2026-11-01", 0), at("2026-11-02", 0), [], hours: withSaturday), 0, "Sunday still off")
    }

    func testSeveralDays() {
        XCTAssertEqual(free(at("2026-10-27", 12), at("2026-10-29", 17), []), 300 + 480 + 480)
    }
}
