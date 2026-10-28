import Foundation
import GRDB
import MCP
import XCTest
@testable import GlyCore
@testable import GlyMCP

/// specs/agent-access "Planning data in the schedule", "Appointment details in the schedule" and "Effort over MCP".
final class PlanningToolTests: XCTestCase {
    var db: DatabaseQueue!
    var source: FakeEventSource!
    var tools: GlyTools!
    var cal = Calendar.current
    var now: Date!

    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        now = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        source = FakeEventSource(calendars: [CalendarInfo(id: "work", title: "Calendar", sourceID: "ex", sourceTitle: "Exchange", colorHex: "#000000")])
        // These tests run on the real date, so every day is a working day here (workweek W1 has its own tests).
        let everyDay = WorkingHours(workdays: Set(1...7))
        tools = GlyTools(writer: db, calendar: source, hiddenCalendarIDs: { [] }, deviceID: "mac-test01", now: { [unowned self] in now },
                         planning: { (everyDay, .defaults(for: everyDay), 5) })
    }

    func call(_ name: String, _ args: [String: Value] = [:]) async -> (Value?, Bool, String) {
        let r = await tools.call(name, arguments: args, client: "claude-code")
        var text = ""; if case .text(let t, _, _)? = r.content.first { text = t }
        return (r.structuredContent, r.isError ?? false, text)
    }
    func field(_ v: Value?, _ k: String) -> Value? { if case .object(let o)? = v { return o[k] } else { return nil } }
    func list(_ v: Value?, _ k: String) -> [Value] { if case .array(let a)? = field(v, k) { return a } else { return [] } }

    func meeting(_ h: Int, _ len: Int, status: ParticipationStatus = .accepted, id: String) -> Appointment {
        let s = cal.date(bySettingHour: h, minute: 0, second: 0, of: now)!
        return Appointment(id: id, calendarID: "work", title: "M\(id)", start: s, end: s.addingTimeInterval(Double(len) * 3600),
                           identity: AppointmentIdentity(calendarID: "work", baseID: id, originalStart: s), availability: .busy, myStatus: status)
    }

    func testPlanningData() async throws {
        source.events = [meeting(10, 2, id: "a"), meeting(13, 1, status: .tentative, id: "b"), meeting(15, 1, status: .declined, id: "c")]
        let tomorrow = LocalDay(date: now).adding(days: 1).description
        _ = await call("create_task", ["title": "Prep", "due_date": .string(tomorrow), "effort": "L"])
        let (v, isError, text) = await call("get_schedule")
        XCTAssertFalse(isError, text)
        XCTAssertEqual(list(v, "appointments").compactMap { if case .string(let s)? = field($0, "counts_as") { s } else { nil } }, ["blocks", "maybe", "free"])
        XCTAssertEqual(field(v, "free_minutes"), .int(480 - 120 - 30))
        // L = 8 h due tomorrow; free after today until tomorrow evening = 8 h → nothing needed today → coming up, start by tomorrow.
        XCTAssertEqual(list(v, "today").count, 0)
        let coming = list(v, "coming_up")
        XCTAssertEqual(coming.count, 1)
        XCTAssertEqual(field(coming.first, "effort"), "L")
        XCTAssertEqual(field(coming.first, "start_by"), .string(tomorrow))
        XCTAssertEqual(field(v, "needed_today_minutes"), .int(0))
        // An M task due today goes into today with its whole effort.
        _ = await call("create_task", ["title": "Today thing", "due_date": .string(LocalDay(date: now).description), "effort": "M"])
        let (v2, _, _) = await call("get_schedule")
        XCTAssertEqual(field(list(v2, "today").first, "reason"), "due_today")
        XCTAssertEqual(field(list(v2, "today").first, "needed_today_minutes"), .int(240))
        XCTAssertEqual(field(list(v2, "today").first, "cant_fit"), .bool(false))
    }

    /// specs/agent-access "Planning data for a later day": planned from the start of that day, horizon after it.
    func testPlanningDataForALaterDay() async throws {
        let today = LocalDay(date: now)
        let later = today.adding(days: 2), inFive = later.adding(days: 5), inSix = later.adding(days: 6)
        _ = await call("create_task", ["title": "Due today", "due_date": .string(today.description), "effort": "S"])
        _ = await call("create_task", ["title": "Due later", "due_date": .string(later.description), "effort": "M"])
        _ = await call("create_task", ["title": "In five", "due_date": .string(inFive.description), "effort": "XS"])
        _ = await call("create_task", ["title": "In six", "due_date": .string(inSix.description), "effort": "XS"])
        let (v, isError, text) = await call("get_schedule", ["date": .string(later.description)])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(field(v, "free_minutes"), .int(480), "the whole working day, no meetings")
        let todayList = list(v, "today")
        XCTAssertEqual(Set(todayList.compactMap { if case .string(let s)? = field($0, "title") { s } else { nil } }), ["Due today", "Due later"])
        XCTAssertEqual(field(todayList.first { field($0, "title") == "Due today" }, "reason"), "overdue")
        XCTAssertEqual(field(v, "needed_today_minutes"), .int(120 + 240))
        XCTAssertEqual(list(v, "coming_up").compactMap { if case .string(let s)? = field($0, "title") { s } else { nil } }, ["In five"],
                       "horizon of 5 days counted from the later day")
    }

    /// specs/agent-access "Appointment details in the schedule": Appointment with an override.
    func testAppointmentWithAnOverride() async throws {
        let a = meeting(10, 1, id: "a"), b = meeting(14, 1, id: "b")
        source.events = [a, b]
        _ = CommandHandler(writer: db).perform(.setBlocking(AppointmentSnapshot(a), scope: .occurrence, value: .ignore), writer: "u")
        let (v, isError, text) = await call("get_schedule")
        XCTAssertFalse(isError, text)
        let appts = list(v, "appointments")
        XCTAssertEqual(appts.map { field($0, "counts_as") }, [.string("free"), .string("blocks")])
        XCTAssertEqual(appts.map { field($0, "reason") }, [.string("override (this occurrence)"), .string("automatic")])
    }

    // MARK: meeting-pages 3.1 (specs/agent-access "Meeting notes over MCP")

    func weekly(_ dayOffset: Int) -> Appointment {
        let s = cal.date(byAdding: .day, value: dayOffset, to: cal.date(bySettingHour: 14, minute: 0, second: 0, of: now)!)!
        return Appointment(id: "w\(dayOffset)", calendarID: "work", title: "1:1 Alex", start: s, end: s.addingTimeInterval(1800),
                           organizer: "Org", identity: AppointmentIdentity(calendarID: "work", baseID: "SERIES", originalStart: s),
                           availability: .busy, isRecurring: true)
    }
    func identity(_ v: Value?) -> [String: Value] {
        ["calendar_id": field(v, "calendar_id") ?? .null, "base_id": field(v, "base_id") ?? .null, "original_start": field(v, "original_start") ?? .null]
    }

    func testAgentPreparesAMeeting() async throws {
        source.events = [weekly(0), weekly(1)]
        let tomorrow = LocalDay(date: now).adding(days: 1).description
        let (before, _, _) = await call("get_schedule", ["date": .string(tomorrow)])
        let appt = list(before, "appointments").first
        XCTAssertEqual(field(appt, "has_notes"), .bool(false))
        XCTAssertEqual(field(appt, "base_id"), "SERIES")
        var args = identity(appt); args["text"] = "- discuss [[project/atlas/Roadmap]]"
        _ = await call("create_page", ["title": "Roadmap", "tags": ["project/atlas"]])
        let (r, isError, text) = await call("update_meeting_notes", args)
        XCTAssertFalse(isError, text)
        let heading = NotesSections.heading(for: LocalDay(date: weekly(1).start), today: LocalDay(date: now))
        guard case .string(let notes)? = field(r, "text") else { return XCTFail("no text") }
        XCTAssertTrue(notes.hasPrefix(heading + "\n- discuss [Roadmap](gly://item/"), notes)
        XCTAssertEqual(field(r, "kind"), "series")
        let (after, _, _) = await call("get_schedule", ["date": .string(tomorrow)])
        XCTAssertEqual(field(list(after, "appointments").first, "has_notes"), .bool(true))
        // The series shares the document: today's occurrence is marked too.
        let (todayV, _, _) = await call("get_schedule")
        XCTAssertEqual(field(list(todayV, "appointments").first, "has_notes"), .bool(true))
    }

    func testReadNotesOfAMeeting() async throws {
        source.events = [weekly(0)]
        let (v, _, _) = await call("get_schedule")
        var args = identity(list(v, "appointments").first)
        args["text"] = "agenda"; args["tags"] = ["person/alex"]
        _ = await call("update_meeting_notes", args)
        let (r, isError, text) = await call("get_meeting_notes", identity(list(v, "appointments").first))
        XCTAssertFalse(isError, text)
        XCTAssertEqual(field(r, "has_notes"), .bool(true))
        XCTAssertEqual(list(r, "tags"), ["person/alex"])
        XCTAssertEqual(field(r, "section"), .string(NotesSections.heading(for: LocalDay(date: now), today: LocalDay(date: now))))
        let (missing, missingError, _) = await call("get_meeting_notes", ["calendar_id": "work", "base_id": "NOPE", "original_start": "2026-01-01T10:00:00Z"])
        XCTAssertTrue(missingError); XCTAssertNil(missing)
    }

    func testAgentEstimatesATask() async throws {
        let (created, _, _) = await call("create_task", ["title": "Estimate me", "effort": "m"])
        XCTAssertEqual(field(created, "effort"), "M")
        guard case .string(let id)? = field(created, "id") else { return XCTFail() }
        let (updated, _, _) = await call("update_task", ["id": .string(id), "effort": .null])
        XCTAssertEqual(field(updated, "effort"), .null)
        let (bad, isError, text) = await call("update_task", ["id": .string(id), "effort": "XXL"])
        XCTAssertNil(bad)
        XCTAssertTrue(isError)
        XCTAssertTrue(text.contains("XS, S, M, L or XL"))
    }
}
