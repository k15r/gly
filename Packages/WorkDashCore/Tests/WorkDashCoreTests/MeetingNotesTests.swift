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

    // MARK: 2.2 commands and queries

    @discardableResult
    func ok(_ c: Command, as writer: String? = nil) -> CommandOK {
        guard case .ok(let r) = h.perform(c, writer: writer ?? me) else { XCTFail("\(c)"); return CommandOK() }
        return r
    }
    func body(_ id: String) throws -> String { try db.read { try String.fetchOne($0, sql: "SELECT body FROM items WHERE id = ?", arguments: [id]) ?? "" } }
    func count(_ sql: String) throws -> Int { try db.read { try Int.fetchOne($0, sql: sql) ?? 0 } }

    func testNothingWritten() throws {
        let r = ok(.saveMeetingNotes(MeetingTarget(appt("S1", day: "2026-11-03")), body: "  "))
        XCTAssertFalse(r.changed)
        XCTAssertEqual(try count("SELECT COUNT(*) FROM items WHERE kind = 'event_note'"), 0)
        XCTAssertEqual(try count("SELECT COUNT(*) FROM series_rules"), 0)
    }

    func testWeeklyOneOnOneThroughCommandsAndUndo() throws {
        let id = ok(.saveMeetingNotes(MeetingTarget(appt("S1", day: "2026-10-27")), body: "## Tue 27 Oct\nfirst\n", session: "s1")).id!
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Edit notes “1:1 Alex”")
        // Another occurrence, same document; the agent appends a dated section on top.
        let r = ok(.appendMeetingNotes(MeetingTarget(appt("S1", day: "2026-11-03")), day: "2026-11-03", markdown: "agreed on scope"), as: "agent:claude-code@mac-test01")
        XCTAssertEqual(r.id, id)
        XCTAssertTrue(try body(id).hasPrefix("## Tue 3 Nov\nagreed on scope"))
        XCTAssertEqual(try count("SELECT COUNT(*) FROM series_rules"), 1)
        XCTAssertEqual(try db.read { try MeetingNotes.document(for: appt("S1", day: "2026-11-10"), db: $0) }.itemID, id)
        // Two saves in one session are one undo step.
        ok(.saveMeetingNotes(MeetingTarget(appt("S1", day: "2026-10-27")), body: "x", session: "s2"))
        ok(.saveMeetingNotes(MeetingTarget(appt("S1", day: "2026-10-27")), body: "xy", session: "s2"))
        try db.write { db in _ = try db.undo(writer: me) }
        XCTAssertTrue(try body(id).hasPrefix("## Tue 3 Nov"), "back to before the session")
    }

    func testLinkFromNotesShowsAsBacklink() throws {
        let page = ok(.createPage(PageDraft(title: "Roadmap", tags: ["project/atlas"]))).id!
        let notes = ok(.saveMeetingNotes(MeetingTarget(appt("S1", day: "2026-11-03")), body: "see [[project/atlas/Roadmap]]")).id!
        XCTAssertEqual(try body(notes), "see [Roadmap](workdash://item/\(page))")
        let back = try db.read { try LinkQueries.backlinks($0, to: page, isTag: false) }
        XCTAssertEqual(back.map(\.source.kind), [.meeting])
        XCTAssertEqual(back.first?.source.title, "1:1 Alex")
    }

    func testMeetingDeletedInTheCalendarIsStillFound() throws {
        let oneOff = appt("W", title: "Workshop", day: "2026-11-04", recurring: false)
        let id = ok(.saveMeetingNotes(MeetingTarget(oneOff), body: "agreed on roadmap scope")).id!
        try db.write { try $0.execute(sql: "UPDATE items SET event_state = 'gone' WHERE id = ?", arguments: [id]) }
        let hits = try db.read { try SearchQueries.search($0, "roadmap scope") }
        XCTAssertEqual(hits.meetings.map(\.ref.id), [id], "Find a meeting by its notes")
        XCTAssertEqual(hits.meetings.first?.ref.kind, .meeting)
    }

    func testBlockingOnlyRowsAreNotMeetings() throws {
        let oneOff = appt("W", title: "Standup", day: "2026-11-04", recurring: false)
        ok(.setBlocking(AppointmentSnapshot(oneOff), scope: .occurrence, value: .ignore))
        XCTAssertEqual(try db.read { try SearchQueries.search($0, "standup") }.meetings, [])
        XCTAssertFalse(try db.read { try MeetingNotes.document(for: oneOff, db: $0) }.hasNotes)
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Ignore “Standup” (this occurrence)", "override labels unchanged")
    }

    func testDeleteAndRestoreNotes() throws {
        let id = ok(.saveMeetingNotes(MeetingTarget(appt("S1", day: "2026-11-03")), body: "## Tue 3 Nov\nx\n", tags: ["person/alex"])).id!
        ok(.deleteMeetingNotes(id: id))
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Delete notes “1:1 Alex”")
        let entry = try XCTUnwrap(try db.read { try TrashQueries.list($0) }.first)
        XCTAssertEqual(entry.kind, .meeting)
        XCTAssertEqual(entry.tags, ["person/alex"])
        ok(.restore(id: id))
        XCTAssertEqual(try body(id), "## Tue 3 Nov\nx\n")
        XCTAssertEqual(try db.read { try MeetingNotes.document(for: appt("S1", day: "2026-11-10"), db: $0) }.itemID, id)
    }

    func testDeletingOneOffNotesKeepsTheBlockingOverride() throws {
        let oneOff = appt("W", title: "Workshop", day: "2026-11-04", recurring: false)
        ok(.setBlocking(AppointmentSnapshot(oneOff), scope: .occurrence, value: .ignore))
        let id = ok(.saveMeetingNotes(MeetingTarget(oneOff), body: "prep")).id!
        ok(.deleteMeetingNotes(id: id))
        XCTAssertEqual(try body(id), "")
        XCTAssertEqual(try db.read { try AnnotationQueries.overrides($0) }.occurrence[oneOff.identity.occurrenceKey], .ignore)
    }

    func testTaggedMeetingInTreeAndOnTagPage() throws {
        let id = ok(.saveMeetingNotes(MeetingTarget(appt("S1", day: "2026-11-03")), body: "notes", tags: ["person/alex"])).id!
        ok(.createPage(PageDraft(title: "Profile", tags: ["person/alex"])))
        let tree = try db.read { try TagQueries.tagTree($0, today: "2026-11-03") }
        let alex = tree.first?.children.first { $0.segment == "alex" }
        XCTAssertEqual(alex?.items.map(\.kind), [.page, .meeting])
        XCTAssertEqual(alex?.items.last?.itemID, id)
        let tagPage = try db.read { try TagPageQueries.page($0, name: try TagName("person"), today: self.today) }
        XCTAssertEqual(tagPage.meetings.map(\.id), [id], "Person's meetings (incl. tags below)")
    }

    func testUpdateExistingNotesByID() throws {
        let id = ok(.saveMeetingNotes(MeetingTarget(appt("S1", day: "2026-11-03")), body: "a")).id!
        ok(.updateMeetingNotes(id: id, body: "b", tags: ["person/alex"]))
        XCTAssertEqual(try body(id), "b")
        XCTAssertEqual(try db.read { try TaskQueries.tagsByItem($0, ids: [id])[id] }, ["person/alex"])
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Edit notes “1:1 Alex”")
    }
}
