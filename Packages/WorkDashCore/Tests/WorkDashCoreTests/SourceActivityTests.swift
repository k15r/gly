import XCTest
@testable import WorkDashCore

final class SourceActivityTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func cal(_ id: String, source: String) -> CalendarInfo { CalendarInfo(id: id, title: id, sourceID: source, sourceTitle: source.uppercased(), colorHex: "#000000") }

    func testOnlyTheChangedSourceGetsANewTimestamp() {
        let fake = FakeEventSource(calendars: [cal("work", source: "exchange"), cal("home", source: "icloud")],
                                   events: [Appointment(id: "w1", calendarID: "work", title: "Sync", start: now, end: now + 1800),
                                            Appointment(id: "h1", calendarID: "home", title: "Dinner", start: now, end: now + 3600)])
        let tracker = SourceActivityTracker(source: fake)
        tracker.baseline(now: now)
        XCTAssertTrue(tracker.statuses().allSatisfy { $0.lastChangeSeen == nil }, "no change seen since launch")

        // Move the work meeting.
        fake.events[0] = Appointment(id: "w1", calendarID: "work", title: "Sync", start: now + 3600, end: now + 5400)
        let later = now + 600
        XCTAssertEqual(tracker.recordChange(now: later), ["exchange"])
        let s = Dictionary(uniqueKeysWithValues: tracker.statuses().map { ($0.sourceID, $0.lastChangeSeen) })
        XCTAssertEqual(s["exchange"], later)
        XCTAssertEqual(s["icloud"], .some(nil))

        // A change notification without actual differences changes nothing.
        XCTAssertEqual(tracker.recordChange(now: later + 60), [])
    }

    func testCancellationAndDeletionCountAsChanges() {
        let fake = FakeEventSource(calendars: [cal("work", source: "exchange")],
                                   events: [Appointment(id: "w1", calendarID: "work", title: "Sync", start: now, end: now + 1800)])
        let tracker = SourceActivityTracker(source: fake)
        tracker.baseline(now: now)
        fake.events[0] = Appointment(id: "w1", calendarID: "work", title: "Sync", start: now, end: now + 1800, isCancelled: true)
        XCTAssertEqual(tracker.recordChange(now: now + 1), ["exchange"])
        fake.events = []
        XCTAssertEqual(tracker.recordChange(now: now + 2), ["exchange"])
    }
}
