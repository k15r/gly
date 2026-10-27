import GRDB
import XCTest
@testable import GlyCore

final class AnnotationReconcilerTests: XCTestCase {
    func testMovedOccurrenceKeepsItsOverrideThroughCalendarChanges() throws {
        let db = try StoreFactory.openInMemory()
        let now = Date()
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: now.addingTimeInterval(86400))!
        let identity = AppointmentIdentity(calendarID: "work", baseID: "SYNC", originalStart: start)
        let original = Appointment(id: "1", calendarID: "work", title: "Weekly sync", start: start, end: start.addingTimeInterval(3600),
                                   organizer: "Organizer A", identity: identity, availability: .busy, myStatus: .accepted)
        let source = FakeEventSource(calendars: [CalendarInfo(id: "work", title: "Calendar", sourceID: "ex", sourceTitle: "Exchange", colorHex: "#000000")],
                                     events: [original])
        _ = CommandHandler(writer: db).perform(.setBlocking(AppointmentSnapshot(original), scope: .occurrence, value: .ignore), writer: "user@test")

        let reconciler = AnnotationReconciler(writer: db, calendar: source, writerName: "system@test", now: { now })
        reconciler.start()

        // The meeting is moved to 15:00 in Outlook; the calendar reports a change.
        let moved = Appointment(id: "1", calendarID: "work", title: "Weekly sync", start: start.addingTimeInterval(5 * 3600),
                                end: start.addingTimeInterval(6 * 3600), organizer: "Organizer A", identity: identity,
                                availability: .busy, myStatus: .accepted)
        source.change { $0.events = [moved] }

        let annotation = try db.read { try AnnotationQueries.annotations($0) }.first!
        XCTAssertEqual(annotation.start, moved.start)
        XCTAssertEqual(try db.read { try AnnotationQueries.overrides($0) }.classify(moved).weight, .free)
        let writers = try db.read { try String.fetchAll($0, sql: "SELECT DISTINCT writer FROM change_log WHERE field = 'event_start'") }
        XCTAssertEqual(Set(writers), ["user@test", "system@test"])

        // Deleted → gone.
        source.change { $0.events = [] }
        XCTAssertEqual(try db.read { try AnnotationQueries.annotations($0) }.first?.state, "gone")
    }

    func testNoCalendarAccessDoesNothing() throws {
        let db = try StoreFactory.openInMemory()
        let r = AnnotationReconciler(writer: db, calendar: FakeEventSource(authorization: .denied), writerName: "system@test")
        XCTAssertNil(r.run())
    }
}
