import GRDB
import XCTest
@testable import GlyCore

/// specs/appointment-annotations "Annotations follow their appointment", "Series overrides follow series splits", "Annotation life cycle".
final class AnnotationMatcherTests: XCTestCase {
    var db: DatabaseQueue!
    var h: CommandHandler!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }()
    func at(_ d: String, _ h: Int) -> Date { cal.date(bySettingHour: h, minute: 0, second: 0, of: LocalDay(d)!.interval(in: cal).start)! }
    func appt(_ day: String, _ hour: Int, base: String = "SYNC", original: Date? = nil, title: String = "Weekly sync",
              organizer: String? = "Organizer A", cancelled: Bool = false) -> Appointment {
        let s = at(day, hour)
        return Appointment(id: base + day, calendarID: "work", title: title, start: s, end: s.addingTimeInterval(3600), isCancelled: cancelled,
                           organizer: organizer, identity: AppointmentIdentity(calendarID: "work", baseID: base, originalStart: original ?? s),
                           availability: .busy, myStatus: .accepted)
    }
    func reconcile(_ appts: [Appointment]) {
        _ = h.perform(.reconcileAnnotations(from: at("2026-10-01", 0), to: at("2026-12-31", 0), appointments: appts.map(ObservedAppointment.init)),
                      writer: "system@test")
    }
    func annotation() throws -> Annotation { try db.read { try AnnotationQueries.annotations($0) }.first! }
    func overrides() throws -> BlockingOverrides { try db.read { try AnnotationQueries.overrides($0) } }

    func testMeetingMovedKeepsItsOverride() throws {
        let original = appt("2026-10-27", 10)
        _ = h.perform(.setBlocking(AppointmentSnapshot(original), scope: .occurrence, value: .ignore), writer: "u")
        // Moved to 14:00: same key (original start from the RID).
        let moved = appt("2026-10-27", 14, original: original.start)
        reconcile([moved])
        XCTAssertEqual(try annotation().start, moved.start, "snapshot follows")
        XCTAssertEqual(try overrides().classify(moved).weight, .free)
    }

    func testKeyMigrationOnUniqueFuzzyMatch() throws {
        let original = appt("2026-10-27", 10)
        _ = h.perform(.setBlocking(AppointmentSnapshot(original), scope: .occurrence, value: .ignore), writer: "u")
        let reKeyed = appt("2026-10-27", 11, base: "SYNC-2")   // the calendar now identifies it differently
        reconcile([reKeyed])
        XCTAssertEqual(try annotation().key, reKeyed.identity.occurrenceKey)
        XCTAssertEqual(try annotation().state, "active")
        XCTAssertEqual(try overrides().classify(reKeyed).weight, .free)
    }

    func testAmbiguousMatchIsNotApplied() throws {
        let original = appt("2026-10-27", 10)
        _ = h.perform(.setBlocking(AppointmentSnapshot(original), scope: .occurrence, value: .ignore), writer: "u")
        let a = appt("2026-10-27", 11, base: "A"), b = appt("2026-10-27", 15, base: "B")
        reconcile([a, b])
        XCTAssertEqual(try annotation().state, "ambiguous")
        XCTAssertEqual(try overrides().classify(a).weight, .blocks)
        XCTAssertEqual(try overrides().classify(b).weight, .blocks)
        // The user picks b.
        _ = h.perform(.resolveAnnotation(id: try annotation().id, to: AppointmentSnapshot(b)), writer: "u")
        XCTAssertEqual(try overrides().classify(b).weight, .free)
    }

    func testAnnotatedMeetingDeletedBecomesGoneAndIsKept() throws {
        let original = appt("2026-10-27", 10)
        _ = h.perform(.setBlocking(AppointmentSnapshot(original), scope: .occurrence, value: .blocks), writer: "u")
        reconcile([])
        XCTAssertEqual(try annotation().state, "gone")
        XCTAssertEqual(try annotation().title, "Weekly sync", "snapshot kept")
        XCTAssertTrue(try overrides().occurrence.isEmpty, "gone annotations don't affect free time")
        reconcile([original])
        XCTAssertEqual(try annotation().state, "active", "comes back when the appointment reappears")
    }

    func testCancelled() throws {
        let original = appt("2026-10-27", 10)
        _ = h.perform(.setBlocking(AppointmentSnapshot(original), scope: .occurrence, value: .blocks), writer: "u")
        reconcile([appt("2026-10-27", 10, cancelled: true)])
        XCTAssertEqual(try annotation().state, "cancelled")
    }

    func testSeriesSplitIsAdopted() throws {
        _ = h.perform(.setBlocking(AppointmentSnapshot(appt("2026-10-27", 10)), scope: .series, value: .optional), writer: "u")
        reconcile([appt("2026-11-04", 9, base: "SYNC-SPLIT")])
        let rule = try db.read { try AnnotationQueries.seriesRules($0) }.first!
        XCTAssertEqual(rule.baseIDs, ["SYNC", "SYNC-SPLIT"])
    }

    func testAnnotationsOutsideTheWindowAreUntouched() throws {
        let far = appt("2027-03-01", 10)
        _ = h.perform(.setBlocking(AppointmentSnapshot(far), scope: .occurrence, value: .ignore), writer: "u")
        reconcile([])
        XCTAssertEqual(try annotation().state, "active")
    }

    func testNothingToDoWritesNothing() throws {
        let original = appt("2026-10-27", 10)
        _ = h.perform(.setBlocking(AppointmentSnapshot(original), scope: .occurrence, value: .ignore), writer: "u")
        let before = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM change_log") }
        reconcile([original])
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM change_log") }, before)
    }
}
