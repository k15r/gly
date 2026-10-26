import Foundation
import GRDB
import MCP
import XCTest
@testable import WorkDashCore
@testable import WorkDashMCP

/// specs/agent-access "Read the schedule of a day" (planning data) and "Effort over MCP".
final class PlanningToolTests: XCTestCase {
    var db: DatabaseQueue!
    var source: FakeEventSource!
    var tools: WorkDashTools!
    var cal = Calendar.current
    var now: Date!

    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        now = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        source = FakeEventSource(calendars: [CalendarInfo(id: "work", title: "Calendar", sourceID: "ex", sourceTitle: "Exchange", colorHex: "#000000")])
        tools = WorkDashTools(writer: db, calendar: source, hiddenCalendarIDs: { [] }, deviceID: "mac-test01", now: { [unowned self] in now })
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
        let work = list(v, "work_on")
        XCTAssertEqual(work.count, 1)
        XCTAssertEqual(field(work.first, "effort"), "L")
        // L = 8 h; free until tomorrow evening = 5.5 h today + 8 h tomorrow = 13.5 h: ≥ 1.5× (12 h), < 2× (16 h) → start today.
        XCTAssertEqual(field(work.first, "state"), "start_today")
        XCTAssertEqual(field(work.first, "free_until_due_minutes"), .int(810))
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
