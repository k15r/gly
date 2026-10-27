import XCTest
@testable import GlyCore

final class LocalDayTests: XCTestCase {
    var berlin: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    func testParsingAndValidation() {
        XCTAssertEqual(LocalDay("2026-10-27")?.description, "2026-10-27")
        XCTAssertNil(LocalDay("2026-02-30"))
        XCTAssertNil(LocalDay("2026-1-5"))
        XCTAssertNil(LocalDay("tomorrow"))
        XCTAssertTrue(LocalDay("2026-10-27")! < LocalDay("2026-11-01")!)
    }

    func testDSTDayIntervals() {
        // Berlin: 2026-10-25 has 25 hours (CEST -> CET), 2026-03-29 has 23 hours.
        XCTAssertEqual(LocalDay("2026-10-25")!.interval(in: berlin).duration, 25 * 3600)
        XCTAssertEqual(LocalDay("2026-03-29")!.interval(in: berlin).duration, 23 * 3600)
        XCTAssertEqual(LocalDay("2026-10-26")!.interval(in: berlin).duration, 24 * 3600)
    }

    func testAddingDaysAcrossDST() {
        XCTAssertEqual(LocalDay("2026-10-24")!.adding(days: 2, calendar: berlin).description, "2026-10-26")
        XCTAssertEqual(LocalDay("2026-03-28")!.adding(days: 1, calendar: berlin).description, "2026-03-29")
    }

    func testWholeDayVsTimedDue() {
        let iso = ISO8601DateFormatter()
        // Whole day: start of the local day.
        XCTAssertEqual(Due(day: "2026-10-30").date(in: berlin).map(iso.string), "2026-10-29T23:00:00Z")
        // Timed: wall-clock time in the local zone (CET, UTC+1 after the switch).
        XCTAssertEqual(Due(day: "2026-10-30", time: "14:00").date(in: berlin).map(iso.string), "2026-10-30T13:00:00Z")
        // Before the switch (CEST, UTC+2).
        XCTAssertEqual(Due(day: "2026-10-24", time: "14:00").date(in: berlin).map(iso.string), "2026-10-24T12:00:00Z")
    }

    func testTimedDueOnTheDSTDayItself() {
        let iso = ISO8601DateFormatter()
        // 2026-10-25 02:30 happens twice in Berlin; 09:00 is unambiguous and must be CET (UTC+1).
        XCTAssertEqual(Due(day: "2026-10-25", time: "09:00").date(in: berlin).map(iso.string), "2026-10-25T08:00:00Z")
    }

    func testDueFromPickedDate() {
        let picked = ISO8601DateFormatter().date(from: "2026-10-30T13:00:00Z")!    // 14:00 in Berlin
        XCTAssertEqual(Due(date: picked, includeTime: true, calendar: berlin), Due(day: "2026-10-30", time: "14:00"))
        XCTAssertEqual(Due(date: picked, includeTime: false, calendar: berlin), Due(day: "2026-10-30"))
    }

    func testFloatingDueKeepsItsDayInAnotherTimeZone() {
        var tokyo = Calendar(identifier: .gregorian); tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let due = Due(day: "2026-10-30")
        XCTAssertEqual(LocalDay(date: due.date(in: tokyo)!, calendar: tokyo).description, "2026-10-30")
        XCTAssertEqual(LocalDay(date: due.date(in: berlin)!, calendar: berlin).description, "2026-10-30")
    }
}
