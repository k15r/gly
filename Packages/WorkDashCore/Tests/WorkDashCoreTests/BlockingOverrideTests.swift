import GRDB
import XCTest
@testable import WorkDashCore

/// specs/appointment-annotations "Blocking override menu" through commands and queries.
final class BlockingOverrideTests: XCTestCase {
    var db: DatabaseQueue!
    var h: CommandHandler!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    let start = Date(timeIntervalSinceReferenceDate: 783_000_000)
    func appt(_ weeks: Int = 0, base: String = "SYNC", title: String = "Weekly sync", organizer: String? = "Organizer A") -> Appointment {
        let s = start.addingTimeInterval(Double(weeks) * 7 * 86400)
        return Appointment(id: "\(weeks)", calendarID: "work", title: title, start: s, end: s.addingTimeInterval(3600), organizer: organizer,
                           identity: AppointmentIdentity(calendarID: "work", baseID: base, originalStart: s), availability: .busy, myStatus: .accepted)
    }
    func overrides() throws -> BlockingOverrides { try db.read { try AnnotationQueries.overrides($0) } }
    func label() throws -> String? { try db.read { try $0.undoLabel(writer: "u") } }
    @discardableResult func set(_ a: Appointment, _ scope: BlockingScope, _ v: BlockingOverride?) -> CommandResult {
        h.perform(.setBlocking(AppointmentSnapshot(a), scope: scope, value: v), writer: "u")
    }

    func testSkipOneMeeting() throws {
        set(appt(0), .occurrence, .ignore)
        XCTAssertEqual(try label(), "Ignore “Weekly sync” (this occurrence)")
        let o = try overrides()
        XCTAssertEqual(o.classify(appt(0)).weight, .free)
        XCTAssertEqual(o.classify(appt(0)).reason, .occurrenceOverride)
        XCTAssertEqual(o.classify(appt(1)).weight, .blocks, "next occurrence still blocks")
        _ = h.perform(.undo, writer: "u")
        XCTAssertEqual(try overrides().classify(appt(0)).weight, .blocks, "one undo step")
    }

    func testOptionalSeries() throws {
        set(appt(0), .series, .optional)
        XCTAssertEqual(try label(), "Optional “Weekly sync” (series)")
        let o = try overrides()
        XCTAssertEqual(o.classify(appt(0)).weight, .maybe)
        XCTAssertEqual(o.classify(appt(5)).weight, .maybe)
        XCTAssertEqual(o.classify(appt(0, base: "OTHER", title: "Other meeting")).weight, .blocks)
    }

    func testBackToAutomatic() throws {
        set(appt(0), .occurrence, .ignore)
        set(appt(0), .occurrence, nil)
        XCTAssertEqual(try label(), "Automatic “Weekly sync” (this occurrence)")
        XCTAssertEqual(try overrides().classify(appt(0)).reason, .automatic)
        XCTAssertFalse(set(appt(3), .occurrence, nil).isOK == false)
        XCTAssertEqual(try db.read { try AnnotationQueries.annotations($0) }.count, 1, "automatic without an annotation creates nothing")
    }

    func testExceptionInAnOptionalSeries() throws {
        set(appt(0), .series, .optional)
        set(appt(2), .occurrence, .blocks)
        let o = try overrides()
        XCTAssertEqual(o.classify(appt(2)).weight, .blocks)
        XCTAssertEqual(o.classify(appt(1)).weight, .maybe)
    }

    func testSeriesRuleFollowsASplitByTitleAndOrganizer() throws {
        set(appt(0), .series, .optional)
        let continuation = appt(4, base: "SYNC-NEW")
        XCTAssertEqual(try overrides().classify(continuation).weight, .maybe)
        XCTAssertEqual(try overrides().classify(appt(4, base: "SYNC-NEW", organizer: "Someone else")).weight, .blocks)
    }
}
