import GRDB
import XCTest
@testable import WorkDashCore

/// Queries behind MCP `list_tasks` and `list_tags` (specs/agent-access).
final class TaskFilterTests: XCTestCase {
    var db: DatabaseQueue!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory() }

    func titles(_ f: TaskFilter) throws -> [String] { try db.read { try TaskQueries.find($0, f).tasks.map(\.title) } }

    func testOpenTasksForAProject() throws {
        try db.write { db in
            try addTask(db, "atlas normal", tags: ["project/atlas"], priority: "normal")
            try addTask(db, "atlas logs urgent", tags: ["project/atlas/logs"], priority: "urgent")
            try addTask(db, "atlas snoozed", tags: ["project/atlas"], status: "snoozed", snoozedUntil: "2026-11-05")
            try addTask(db, "atlas done", tags: ["project/atlas"], status: "done")
            try addTask(db, "other", tags: ["project/other"])
        }
        XCTAssertEqual(try titles(TaskFilter(tag: try TagName("project/atlas"))), ["atlas logs urgent", "atlas normal", "atlas snoozed"])
    }

    func testOverdueTasks() throws {
        try db.write { db in
            try addTask(db, "due yesterday", dueDay: "2026-10-25")
            try addTask(db, "due long ago", dueDay: "2026-09-01")
            try addTask(db, "due today", dueDay: "2026-10-26")
            try addTask(db, "no due")
            try addTask(db, "done overdue", status: "done", dueDay: "2026-10-20")
        }
        XCTAssertEqual(try titles(TaskFilter(dueBefore: "2026-10-25")), ["due long ago", "due yesterday"])
        XCTAssertEqual(try titles(TaskFilter(dueAfter: "2026-10-26")), ["due today"])
    }

    func testTruncatedResult() throws {
        try db.write { db in for n in 0..<80 { try addTask(db, "task \(n)") } }
        let page = try db.read { try TaskQueries.find($0, TaskFilter()) }
        XCTAssertEqual(page.tasks.count, 50)
        XCTAssertTrue(page.hasMore)
        let all = try db.read { try TaskQueries.find($0, TaskFilter(limit: 100)) }
        XCTAssertEqual(all.tasks.count, 80)
        XCTAssertFalse(all.hasMore)
    }

    func testTextStatusesAndEscaping() throws {
        try db.write { db in
            try addTask(db, "Send Load-Test report")
            try addTask(db, "100% done", status: "done")
            try addTask(db, "100 items", status: "dropped")
        }
        XCTAssertEqual(try titles(TaskFilter(text: "load-test")), ["Send Load-Test report"])
        XCTAssertEqual(try titles(TaskFilter(statuses: [], text: "100%")), ["100% done"], "% is literal")
        XCTAssertEqual(try titles(TaskFilter(statuses: [])), ["Send Load-Test report", "100% done", "100 items"], "open first, then done, dropped")
    }

    func testTagsBelowAPrefix() throws {
        try db.write { db in
            try addTask(db, "a", tags: ["person/alex"])
            try addTask(db, "b", tags: ["person/alex"])
            try addTask(db, "c", tags: ["person/sam"], status: "done")
            try addTask(db, "d", tags: ["project/atlas"])
        }
        let tags = try db.read { try TagQueries.list($0, prefix: "person/", today: "2026-10-26") }
        XCTAssertEqual(tags, [TagCount(name: "person/alex", openCount: 2), TagCount(name: "person/sam", openCount: 0)])
        XCTAssertEqual(try db.read { try TagQueries.list($0, today: "2026-10-26") }.count, 3)
    }
}
