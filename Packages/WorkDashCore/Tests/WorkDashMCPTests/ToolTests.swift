import Foundation
import GRDB
import MCP
import XCTest
@testable import WorkDashCore
@testable import WorkDashMCP

/// specs/agent-access scenarios, exercised through `WorkDashTools` (and the server for raw JSON-RPC).
final class ToolTests: XCTestCase {
    var db: DatabaseQueue!
    var calendar: FakeEventSource!
    var hidden: Set<String> = []
    var tools: WorkDashTools!
    /// Monday 26 Oct 2026, 10:00 local.
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 10))!

    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        calendar = FakeEventSource(calendars: [
            CalendarInfo(id: "work", title: "Calendar", sourceID: "ex", sourceTitle: "Exchange", colorHex: "#0000FF"),
            CalendarInfo(id: "bday", title: "Birthdays", sourceID: "other", sourceTitle: "Other", colorHex: "#FF0000"),
        ])
        tools = WorkDashTools(writer: db, calendar: calendar, hiddenCalendarIDs: { [unowned self] in hidden },
                              deviceID: "mac-test01", now: { [now] in now })
    }

    // MARK: Helpers

    struct Outcome { let value: Value?; let isError: Bool; let text: String }

    func call(_ name: String, _ args: [String: Value] = [:], client: String? = "claude-code") async -> Outcome {
        let r = await tools.call(name, arguments: args, client: client)
        var text = ""
        if case .text(let t, _, _)? = r.content.first { text = t }
        return Outcome(value: r.structuredContent, isError: r.isError ?? false, text: text)
    }

    func field(_ v: Value?, _ key: String) -> Value? { if case .object(let o)? = v { return o[key] } else { return nil } }
    func str(_ v: Value?, _ key: String) -> String? { if case .string(let s)? = field(v, key) { return s } else { return nil } }
    func list(_ v: Value?, _ key: String) -> [Value] { if case .array(let a)? = field(v, key) { return a } else { return [] } }
    func titles(_ v: Value?, _ key: String = "tasks") -> [String] { list(v, key).compactMap { str($0, "title") } }

    func at(_ hour: Int, _ minute: Int = 0, day: Int = 26) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: 3.2 definitions and encoding

    func testToolListHasAllSevenWithSchemas() {
        let names = ToolDefinitions.all.map(\.name)
        XCTAssertEqual(names, ["get_schedule", "list_tasks", "get_task", "create_task", "update_task", "delete_task", "list_tags"])
        for tool in ToolDefinitions.all {
            XCTAssertFalse(tool.description?.isEmpty ?? true, tool.name)
            guard case .object(let schema) = tool.inputSchema else { return XCTFail("\(tool.name) schema") }
            XCTAssertEqual(schema["type"], "object", tool.name)
        }
        XCTAssertTrue(ToolDefinitions.all[0].description!.contains("YYYY-MM-DD"))
    }

    func testEncodedTaskShape() async throws {
        let id = try await db.write { try addTask($0, "Send report", tags: ["project/atlas"], priority: "high", dueDay: "2026-10-29", dueTime: "14:00", writer: "user@mac") }
        let task = await call("get_task", ["id": .string(id)])
        var json = WorkDashTools.json(task.value!)
        for key in ["created_at", "modified_at"] {
            json = json.replacingOccurrences(of: #""\#(key)":"[^"]*""#, with: #""\#(key)":"T""#, options: .regularExpression)
        }
        XCTAssertEqual(json, #"{"created_at":"T","due":{"day":"2026-10-29","time":"14:00"},"id":"\#(id)","modified_at":"T","modified_by":"user@mac","notes":"","priority":"high","snoozed_until":null,"status":"open","tags":["project/atlas"],"title":"Send report"}"#)
    }

    // MARK: 3.3 read tools

    func testGetTaskExistingUnknownAndDeleted() async throws {
        let id = try await db.write { try addTask($0, "A") }
        let ok = await call("get_task", ["id": .string(id)])
        XCTAssertFalse(ok.isError)
        XCTAssertEqual(str(ok.value, "title"), "A")

        let unknown = await call("get_task", ["id": "nope"])
        XCTAssertTrue(unknown.isError)
        XCTAssertTrue(unknown.text.contains("not found"))

        _ = await call("delete_task", ["id": .string(id)])
        let deleted = await call("get_task", ["id": .string(id)])
        XCTAssertTrue(deleted.isError)
    }

    func testListTasksArgumentValidation() async throws {
        let badDate = await call("list_tasks", ["due_before": "next friday"])
        XCTAssertTrue(badDate.isError)
        XCTAssertTrue(badDate.text.contains("YYYY-MM-DD"))
        let badStatus = await call("list_tasks", ["status": "waiting"])
        XCTAssertTrue(badStatus.isError)
        XCTAssertTrue(badStatus.text.contains("Unknown status"))
        let badTag = await call("list_tasks", ["tag": "project//x"])
        XCTAssertTrue(badTag.isError)
    }

    func testListTasksAndTags() async throws {
        try await db.write { db in
            try addTask(db, "atlas", tags: ["project/atlas"], dueDay: "2026-10-20")
            try addTask(db, "other", tags: ["person/alex"])
        }
        let atlas = await call("list_tasks", ["tag": "project"])
        XCTAssertEqual(titles(atlas.value), ["atlas"])
        XCTAssertEqual(field(atlas.value, "has_more"), .bool(false))
        let overdue = await call("list_tasks", ["due_before": "2026-10-25"])
        XCTAssertEqual(titles(overdue.value), ["atlas"])
        let tags = await call("list_tags", ["prefix": "person/"])
        XCTAssertEqual(list(tags.value, "tags"), [.object(["name": "person/alex", "open_tasks": .int(1)])])
    }

    // MARK: 3.4 write tools

    func testCreateTaskFromAnEmail() async throws {
        let r = await call("create_task", ["title": "Send load-test report", "priority": "high", "due_date": "2026-10-29", "tags": ["project/atlas"]])
        XCTAssertFalse(r.isError, r.text)
        XCTAssertEqual(str(r.value, "priority"), "high")
        XCTAssertEqual(field(r.value, "due"), .object(["day": "2026-10-29"]))
        XCTAssertEqual(list(r.value, "tags"), ["project/atlas"])
        XCTAssertEqual(str(r.value, "modified_by"), "agent:claude-code@mac-test01")
    }

    func testCreateTaskInvalidInput() async throws {
        let empty = await call("create_task", ["title": "  "])
        XCTAssertTrue(empty.isError)
        XCTAssertTrue(empty.text.contains("title"))
        let badTag = await call("create_task", ["title": "x", "tags": ["project//x"]])
        XCTAssertTrue(badTag.isError)
        XCTAssertTrue(badTag.text.lowercased().contains("empty"), badTag.text)
        let v1 = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM items") }
        XCTAssertEqual(v1, 0)
    }

    func testCompleteSnoozeAndPartialUpdate() async throws {
        let created = await call("create_task", ["title": "A", "notes": "n", "priority": "normal", "due_date": "2026-10-27", "tags": ["person/alex"]])
        let id = str(created.value, "id")!

        let noDate = await call("update_task", ["id": .string(id), "status": "snoozed"])
        XCTAssertTrue(noDate.isError)
        XCTAssertTrue(noDate.text.contains("snoozed_until"))

        let batchesBefore = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT batch) FROM change_log") }!
        let partial = await call("update_task", ["id": .string(id), "priority": "urgent"])
        XCTAssertEqual(str(partial.value, "priority"), "urgent")
        XCTAssertEqual(str(partial.value, "notes"), "n")
        XCTAssertEqual(field(partial.value, "due"), .object(["day": "2026-10-27"]))
        XCTAssertEqual(list(partial.value, "tags"), ["person/alex"])

        let multi = await call("update_task", ["id": .string(id), "title": "B", "tags": ["project/atlas"], "status": "snoozed", "snoozed_until": "2026-10-28", "due_date": .null])
        XCTAssertFalse(multi.isError, multi.text)
        XCTAssertEqual(field(multi.value, "due"), .null)
        let batchesAfter = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT batch) FROM change_log") }!
        XCTAssertEqual(batchesAfter - batchesBefore, 2, "each update_task call is one batch")

        let done = await call("update_task", ["id": .string(id), "status": "done"])
        XCTAssertEqual(str(done.value, "status"), "done")
        let open = await call("list_tasks")
        XCTAssertEqual(titles(open.value), [])
    }

    func testAgentDeletesATaskAndHistoryIsKept() async throws {
        let id = str(await call("create_task", ["title": "A", "tags": ["person/alex"]]).value, "id")!
        let r = await call("delete_task", ["id": .string(id)])
        XCTAssertEqual(r.value, .object(["deleted": .string(id)]))
        try await db.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items"), 0)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT title FROM items WHERE id = ?", arguments: [id]), "A")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT DISTINCT writer FROM change_log WHERE op = 'delete'"), "agent:claude-code@mac-test01")
        }
    }

    func testUserUndoLeavesTheAgentsChange() async throws {
        let handler = CommandHandler(writer: db)
        guard case .ok(let a) = handler.perform(.createTask(TaskDraft(title: "A")), writer: "user@mac-test01") else { return XCTFail() }
        _ = handler.perform(.updateTask(id: a.id!, TaskPatch(title: "A edited")), writer: "user@mac-test01")
        let b = str(await call("create_task", ["title": "B"]).value, "id")!
        _ = await call("update_task", ["id": .string(b), "title": "B by agent"])
        _ = handler.perform(.undo, writer: "user@mac-test01")
        let r2 = await call("get_task", ["id": .string(a.id!)])
        XCTAssertEqual(str(r2.value, "title"), "A")
        let r3 = await call("get_task", ["id": .string(b)])
        XCTAssertEqual(str(r3.value, "title"), "B by agent")
    }

    func testWriterSanitizing() {
        XCTAssertEqual(tools.writer(client: "Claude Code"), "agent:claude-code@mac-test01")
        XCTAssertEqual(tools.writer(client: nil), "agent:unknown@mac-test01")
        XCTAssertEqual(WorkDashTools.sanitize(String(repeating: "x", count: 60)).count, 40)
    }

    // MARK: 3.5 get_schedule

    func addEvents() {
        calendar.events = [
            Appointment(id: "1", calendarID: "work", title: "Standup", start: at(9), end: at(9, 15), location: "Room 1", organizer: "Organizer A", attendees: ["Person A"]),
            Appointment(id: "2", calendarID: "work", title: "Review", start: at(13), end: at(14)),
            Appointment(id: "3", calendarID: "bday", title: "Birthday", start: at(0), end: at(0, day: 27), isAllDay: true),
            Appointment(id: "4", calendarID: "work", title: "Wednesday sync", start: at(10, day: 28), end: at(11, day: 28)),
        ]
    }

    func testTodaysSchedule() async throws {
        addEvents()
        try await db.write { db in
            try addTask(db, "due today", dueDay: "2026-10-26")
            try addTask(db, "overdue", dueDay: "2026-10-20")
            try addTask(db, "later", dueDay: "2026-10-28")
        }
        let r = await call("get_schedule")
        XCTAssertEqual(str(r.value, "date"), "2026-10-26")
        XCTAssertEqual(list(r.value, "appointments").compactMap { str($0, "title") }, ["Birthday", "Standup", "Review"])
        let standup = list(r.value, "appointments")[1]
        XCTAssertEqual(str(standup, "calendar"), "Calendar (Exchange)")
        XCTAssertEqual(str(standup, "location"), "Room 1")
        XCTAssertEqual(Set(titles(r.value)), ["due today", "overdue"])
        let overdue = list(r.value, "tasks").first { str($0, "title") == "overdue" }
        XCTAssertEqual(field(overdue, "overdue"), .bool(true))
        XCTAssertNil(field(r.value, "appointments_unavailable"))
    }

    func testAnotherDay() async throws {
        addEvents()
        try await db.write { db in
            try addTask(db, "overdue", dueDay: "2026-10-20")
            try addTask(db, "wednesday", dueDay: "2026-10-28")
        }
        let r = await call("get_schedule", ["date": "2026-10-28"])
        XCTAssertEqual(list(r.value, "appointments").compactMap { str($0, "title") }, ["Wednesday sync"])
        XCTAssertEqual(titles(r.value), ["wednesday"])
    }

    func testNoCalendarAccess() async throws {
        addEvents()
        calendar.authorization = .denied
        try await db.write { try addTask($0, "due today", dueDay: "2026-10-26") }
        let r = await call("get_schedule")
        XCTAssertFalse(r.isError)
        XCTAssertEqual(titles(r.value), ["due today"])
        XCTAssertEqual(list(r.value, "appointments"), [])
        XCTAssertNotNil(str(r.value, "appointments_unavailable"))
    }

    func testHiddenCalendarAndAgents() async throws {
        addEvents()
        hidden = ["bday"]
        let r = await call("get_schedule")
        XCTAssertEqual(list(r.value, "appointments").compactMap { str($0, "title") }, ["Standup", "Review"])
    }

    // MARK: 3.6 raw JSON-RPC through the server

    func reply(_ server: WorkDashMCPServer, _ json: String, client: String? = "test") async -> [String: Any]? {
        guard let data = await server.handleStdio(Data(json.utf8), client: client) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func testRawMessages() async throws {
        let server = try await WorkDashMCPServer(tools: tools)
        let initialize = await reply(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#)
        XCTAssertEqual(initialize?["id"] as? Int, 1, "original id restored")
        XCTAssertNotNil((initialize?["result"] as? [String: Any])?["serverInfo"])

        let second = await reply(server, #"{"jsonrpc":"2.0","id":9,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"other","version":"1"}}}"#)
        XCTAssertNotNil((second?["result"] as? [String: Any])?["serverInfo"], "a second client can initialize too")

        let note = await reply(server, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(note)

        let list = await reply(server, #"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#)
        XCTAssertEqual(((list?["result"] as? [String: Any])?["tools"] as? [Any])?.count, 7)

        let ping = await reply(server, #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)
        XCTAssertNotNil(ping?["result"])

        let created = await reply(server, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"create_task","arguments":{"title":"Via stdio"}}}"#, client: "Claude Code")
        XCTAssertEqual((created?["result"] as? [String: Any])?["isError"] as? Bool ?? false, false)
        let v4 = try await db.read { try String.fetchOne($0, sql: "SELECT modified_by FROM items") }
        XCTAssertEqual(v4, "agent:claude-code@mac-test01")

        let malformed = await reply(server, "{not json")
        XCTAssertNotNil(malformed?["error"])
    }

    func testConcurrentClientsWithTheSameID() async throws {
        let server = try await WorkDashMCPServer(tools: tools)
        async let a = reply(server, #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_task","arguments":{"title":"from A"}}}"#, client: "a")
        async let b = reply(server, #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_task","arguments":{"title":"from B"}}}"#, client: "b")
        let (ra, rb) = await (a, b)
        XCTAssertEqual(ra?["id"] as? Int, 1)
        XCTAssertEqual(rb?["id"] as? Int, 1)
        let v5 = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM items") }
        XCTAssertEqual(v5, 2)
    }
}
