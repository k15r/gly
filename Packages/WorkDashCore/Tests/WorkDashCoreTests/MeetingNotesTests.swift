import GRDB
import XCTest
@testable import WorkDashCore

/// specs/meeting-pages; design N1–N4.
final class MeetingNotesTests: XCTestCase {
    let me = "user@mac-test01"
    var db: DatabaseQueue!
    var h: CommandHandler!
    let today = LocalDay("2026-11-03")!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    func appt(_ base: String, title: String = "1:1 Alex", day: String, recurring: Bool = true, organizer: String? = "Org") -> Appointment {
        let start = ISO8601DateFormatter().date(from: "\(day)T13:00:00Z")!
        return Appointment(id: "\(base)|\(day)", calendarID: "work", title: title, start: start, end: start.addingTimeInterval(1800),
                           organizer: organizer, identity: AppointmentIdentity(calendarID: "work", baseID: base, originalStart: start),
                           isRecurring: recurring)
    }

    // MARK: 2.1 sections

    func testHeadingFormat() {
        XCTAssertEqual(NotesSections.heading(for: LocalDay("2026-11-03")!, today: today), "## Tue 3 Nov")
        XCTAssertEqual(NotesSections.heading(for: LocalDay("2025-12-30")!, today: today), "## Tue 30 Dec 2025")
    }

    func testWriteTodaysNotesNewestOnTop() {
        let body = "## Tue 27 Oct\n- earlier\n"
        let result = NotesSections.insert("agreed on scope", for: today, into: body, today: today)
        XCTAssertEqual(result, "## Tue 3 Nov\nagreed on scope\n\n## Tue 27 Oct\n- earlier\n")
    }

    func testAppendToSameDayAndOlderSection() {
        var body = NotesSections.insert("first", for: today, into: "", today: today)
        body = NotesSections.insert("second", for: today, into: body, today: today)
        XCTAssertEqual(body, "## Tue 3 Nov\nfirst\nsecond\n")
        body = NotesSections.insert("old", for: LocalDay("2026-10-20")!, into: body, today: today)
        XCTAssertEqual(body, "## Tue 3 Nov\nfirst\nsecond\n\n## Tue 20 Oct\nold\n", "older dates go below")
        body = NotesSections.insert("middle", for: LocalDay("2026-10-27")!, into: body, today: today)
        XCTAssertEqual(NotesSections.sections(in: body, today: today).map(\.day.description), ["2026-11-03", "2026-10-27", "2026-10-20"])
    }

    func testOpenAnEarlierMeetingFindsItsSection() {
        let body = "Intro\n\n## Tue 3 Nov\nnew\n\n## Tue 27 Oct\nold stuff\n"
        let s = NotesSections.section(for: LocalDay("2026-10-27")!, in: body, today: today)
        XCTAssertEqual((body as NSString).substring(from: s!.contentStart), "old stuff\n")
        XCTAssertNil(NotesSections.section(for: LocalDay("2026-10-13")!, in: body, today: today))
        XCTAssertEqual(NotesSections.sections(in: "## Wed 30 Dec\nx", today: LocalDay("2027-01-04")!).first?.day.description, "2026-12-30",
                       "a December heading read in January belongs to last year")
    }

    // MARK: 2.1 resolver

    func insertSeriesNote(rule: String, body: String) throws {
        try db.write { db in
            try Batch(db: db, writer: me).insert("items", ["kind": "event_note", "title": "1:1 Alex", "body": body, "series_rule": rule])
        }
    }
    func insertRule(base: String) throws -> String {
        try db.write { db in
            try Batch(db: db, writer: me).insert("series_rules", ["calendar_id": "work", "title": "1:1 Alex", "organizer": "Org",
                                                                   "base_ids": AnnotationQueries.encodeIDs([base])])
        }
    }

    func testWeeklyOneOnOneSharesOneDocument() throws {
        let rule = try insertRule(base: "S1")
        try insertSeriesNote(rule: rule, body: "## Tue 27 Oct\nx\n")
        let a = try db.read { try MeetingNotes.document(for: appt("S1", day: "2026-10-27"), db: $0) }
        let b = try db.read { try MeetingNotes.document(for: appt("S1", day: "2026-11-03"), db: $0) }
        XCTAssertEqual(a.target, .series(ruleID: rule))
        XCTAssertEqual(a.itemID, b.itemID)
        XCTAssertTrue(b.hasNotes)
    }

    func testSeriesSplitKeepsTheDocument() throws {
        let rule = try insertRule(base: "S1")
        try insertSeriesNote(rule: rule, body: "notes")
        let afterSplit = try db.read { try MeetingNotes.document(for: appt("S1-new", day: "2026-11-10"), db: $0) }
        XCTAssertEqual(afterSplit.target, .series(ruleID: rule), "same calendar, title and organizer continue the series")
        XCTAssertEqual(afterSplit.body, "notes")
    }

    func testOneOffAndUnknownSeries() throws {
        let oneOff = appt("X", title: "Workshop", day: "2026-11-04", recurring: false)
        let r = try db.read { try MeetingNotes.document(for: oneOff, db: $0) }
        XCTAssertEqual(r.target, .occurrence(key: oneOff.identity.occurrenceKey))
        XCTAssertNil(r.itemID)
        XCTAssertFalse(r.hasNotes)
        let fresh = try db.read { try MeetingNotes.document(for: appt("NEW", title: "Retro", day: "2026-11-04"), db: $0) }
        XCTAssertEqual(fresh.target, .series(ruleID: nil), "no rule yet: created on first save")
    }

    func testMigrationFromV4() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue, upTo: "v4")
        try queue.write { try $0.execute(sql: "INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, status, priority) VALUES ('T', '2026-10-27', '2026-10-27', 'u', 'task', 'Old', 'open', 'none')") }
        try Schema.migrator.migrate(queue)
        XCTAssertNil(try queue.read { try String.fetchOne($0, sql: "SELECT series_rule FROM items WHERE id = 'T'") })
    }
}
