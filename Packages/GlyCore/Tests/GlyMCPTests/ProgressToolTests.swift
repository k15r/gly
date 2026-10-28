import Foundation
import GRDB
import MCP
import XCTest
@testable import GlyCore
@testable import GlyMCP

/// specs/agent-access "Progress over MCP" (task-progress P6).
final class ProgressToolTests: XCTestCase {
    var db: DatabaseQueue!
    var tools: GlyTools!
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }()
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 10))!

    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        tools = GlyTools(writer: db, calendar: FakeEventSource(), hiddenCalendarIDs: { [] }, deviceID: "mac-test01",
                         now: { [unowned self] in now })
    }

    func call(_ name: String, _ args: [String: Value]) async -> (Value?, Bool, String) {
        let r = await tools.call(name, arguments: args, client: "claude-code")
        var text = ""; if case .text(let t, _, _)? = r.content.first { text = t }
        return (r.structuredContent, r.isError ?? false, text)
    }
    func field(_ v: Value?, _ k: String) -> Value? { if case .object(let o)? = v { return o[k] } else { return nil } }
    func newTask(effort: String?) async -> String {
        var args: [String: Value] = ["title": "Report", "due_date": "2026-11-03"]
        if let effort { args["effort"] = .string(effort) }
        let (v, _, _) = await call("create_task", args)
        if case .string(let id)? = field(v, "id") { return id }
        XCTFail("create failed"); return ""
    }

    func testTaskResultsCarryProgress() async throws {
        let id = await newTask(effort: "XL")
        let (v, _, _) = await call("get_task", ["id": .string(id)])
        XCTAssertEqual(field(v, "remaining_minutes"), .int(1440))
        XCTAssertEqual(field(v, "worked_minutes"), .int(0))
        let plain = await newTask(effort: nil)
        let (p, _, _) = await call("get_task", ["id": .string(plain)])
        XCTAssertEqual(field(p, "remaining_minutes"), .null)
        XCTAssertEqual(field(p, "worked_minutes"), .null)
    }

    func testAgentRecordsWork() async throws {
        // "Agent records work": +2 h worked, 2 h less remaining, one history step attributed to the agent.
        let id = await newTask(effort: "XL")
        let (v, isError, text) = await call("record_work", ["id": .string(id), "minutes": 120])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(field(v, "worked_minutes"), .int(120))
        XCTAssertEqual(field(v, "remaining_minutes"), .int(1320))
        let rows = try await db.read { db in
            try Row.fetchAll(db, sql: "SELECT day, kind FROM task_work").map { "\($0["day"] as String) \($0["kind"] as String)" }
        }
        XCTAssertEqual(rows, ["2026-10-28 agent"], "default: today, recorded as the agent's work")
        let writers = try await db.read { try String.fetchAll($0, sql: "SELECT DISTINCT writer FROM change_log WHERE table_name = 'task_work'") }
        XCTAssertEqual(writers, ["agent:claude-code@mac-test01"])
        let batches = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT batch) FROM change_log WHERE table_name = 'task_work'") }
        XCTAssertEqual(batches, 1)
    }

    func testAgentSetsWhatsLeft() async throws {
        // "Agent sets what's left": XL, remaining_minutes 240 → 4 h left; together with other fields one step.
        let id = await newTask(effort: "XL")
        let (v, isError, text) = await call("update_task", ["id": .string(id), "remaining_minutes": 240, "priority": "high"])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(field(v, "remaining_minutes"), .int(240))
        XCTAssertEqual(field(v, "priority"), "high")
        let batches = try await db.read { try String.fetchAll($0, sql: "SELECT DISTINCT batch FROM change_log WHERE writer LIKE 'agent:%'") }
        XCTAssertEqual(batches.count, 2, "create + one update step")
    }

    func testRemainingNeedsAnEffort() async throws {
        let id = await newTask(effort: nil)
        let (_, isError, text) = await call("update_task", ["id": .string(id), "remaining_minutes": 60])
        XCTAssertTrue(isError)
        XCTAssertTrue(text.contains("effort"), text)
        // Setting the effort in the same call works.
        let (v, isError2, _) = await call("update_task", ["id": .string(id), "effort": "L", "remaining_minutes": 60])
        XCTAssertFalse(isError2)
        XCTAssertEqual(field(v, "remaining_minutes"), .int(60))
    }

    func testRecordWorkForAnotherDay() async throws {
        let id = await newTask(effort: "L")
        _ = await call("record_work", ["id": .string(id), "minutes": 60, "date": "2026-10-27"])
        let day = try await db.read { try String.fetchOne($0, sql: "SELECT day FROM task_work") }
        XCTAssertEqual(day, "2026-10-27")
    }

    // MARK: specs/agent-access "Parts over MCP" (subtasks S6)

    func parts(_ v: Value?) -> [[String: Value]] {
        guard case .array(let a)? = field(v, "parts") else { return [] }
        return a.compactMap { if case .object(let o) = $0 { o } else { nil } }
    }

    func testAgentBreaksATaskDown() async throws {
        let (v, isError, text) = await call("create_task", ["title": "Trip", "effort": "XL", "parts": .array([
            .object(["title": "Book", "effort": "S"]), .object(["title": "Pack"]), .object(["title": "Travel", "effort": "L"]),
        ])])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(parts(v).compactMap { if case .string(let s)? = $0["title"] { s } else { nil } }, ["Book", "Pack", "Travel"])
        XCTAssertEqual(field(v, "remaining_minutes"), .int(120 + 480), "sum of the estimated open parts")
    }

    func testAgentTicksOffAPart() async throws {
        let (created, _, _) = await call("create_task", ["title": "Trip", "parts": .array([
            .object(["title": "Book", "effort": "S"]), .object(["title": "Pack", "effort": "S"]),
        ])])
        guard case .string(let id)? = field(created, "id") else { return XCTFail() }
        var list = parts(created)
        list[0]["done"] = .bool(true)
        let (v, isError, text) = await call("update_task", ["id": .string(id), "parts": .array(list.map { .object($0) })])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(parts(v).map { $0["done"] }, [.bool(true), .bool(false)])
        XCTAssertEqual(parts(v).map { $0["id"] }, list.map { $0["id"] }, "same parts, by id")
        XCTAssertEqual(field(v, "remaining_minutes"), .int(120))
        let batches = try await db.read { try String.fetchAll($0, sql: "SELECT DISTINCT batch FROM change_log WHERE table_name = 'task_parts'") }
        XCTAssertEqual(batches.count, 2, "create + one update step")
        let writers = try await db.read { try String.fetchAll($0, sql: "SELECT DISTINCT writer FROM change_log WHERE table_name = 'task_parts'") }
        XCTAssertEqual(writers, ["agent:claude-code@mac-test01"])
    }

    func testBadPartIsAClearError() async throws {
        let (_, isError, text) = await call("create_task", ["title": "Trip", "parts": .array([.object(["effort": "S"])])])
        XCTAssertTrue(isError)
        XCTAssertTrue(text.contains("title"), text)
    }
}
