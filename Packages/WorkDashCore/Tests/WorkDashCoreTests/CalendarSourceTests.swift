import XCTest
@testable import WorkDashCore

final class CalendarSourceTests: XCTestCase {
    func testCancellationRule() {
        XCTAssertEqual(CancellationRule.apply(title: "Canceled: Weekly sync", statusCancelled: false).title, "Weekly sync")
        XCTAssertTrue(CancellationRule.apply(title: "Canceled: Weekly sync", statusCancelled: false).isCancelled)
        XCTAssertTrue(CancellationRule.apply(title: "ABGESAGT: Abstimmung", statusCancelled: false).isCancelled)
        XCTAssertTrue(CancellationRule.apply(title: "Cancelled:Review", statusCancelled: false).isCancelled)
        XCTAssertEqual(CancellationRule.apply(title: "Cancelled:Review", statusCancelled: false).title, "Review")
        XCTAssertTrue(CancellationRule.apply(title: "Weekly sync", statusCancelled: true).isCancelled, "status alone counts")
        XCTAssertFalse(CancellationRule.apply(title: "Discuss canceled: items", statusCancelled: false).isCancelled, "only a prefix counts")
        XCTAssertEqual(CancellationRule.apply(title: "Canceled:", statusCancelled: false).title, "Canceled:", "keeps a bare prefix as title")
    }

    func testFakeSourceFiltersByCalendarAndOverlap() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let fake = FakeEventSource(calendars: [CalendarInfo(id: "a", title: "A", sourceID: "s", sourceTitle: "S", colorHex: "#FF0000")],
                                   events: [Appointment(id: "1", calendarID: "a", title: "in", start: start, end: start + 3600),
                                            Appointment(id: "2", calendarID: "b", title: "other cal", start: start, end: start + 3600),
                                            Appointment(id: "3", calendarID: "a", title: "later", start: start + 90000, end: start + 93600)])
        let found = fake.appointments(overlapping: DateInterval(start: start - 60, duration: 7200), calendarIDs: ["a"])
        XCTAssertEqual(found.map(\.title), ["in"])
        var changes = 0
        fake.onChange = { changes += 1 }
        fake.change { _ in }
        XCTAssertEqual(changes, 1)
    }

    func testHexColor() {
        XCTAssertEqual(EventKitSource.hex(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)), "#FF8000")
        XCTAssertEqual(EventKitSource.hex(nil), "#888888")
    }
}
