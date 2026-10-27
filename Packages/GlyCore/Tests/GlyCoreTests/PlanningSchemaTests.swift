import GRDB
import XCTest
@testable import GlyCore

final class PlanningSchemaTests: XCTestCase {
    func testV4ColumnsTableAndConstraints() throws {
        let db = try StoreFactory.openInMemory()
        try db.read { db in
            let cols = Set(try db.columns(in: "items").map(\.name))
            for c in ["effort", "event_key", "event_series", "event_calendar", "event_start", "event_end", "event_organizer", "event_state", "blocking"] {
                XCTAssertTrue(cols.contains(c), c)
            }
            XCTAssertTrue(try db.tableExists("series_rules"))
            XCTAssertTrue(try db.viewExists("live_series_rules"))
        }
        XCTAssertTrue(Schema.syncedTables.contains("series_rules"))
        XCTAssertThrowsError(try db.write { try $0.execute(sql: """
            INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, effort) VALUES ('x', '2026-10-26', '2026-10-26', 'u', 'task', 't', 'XXL')
            """) })
    }

    func testMigrationFromV3() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue, upTo: "v3-rebuild-derived")
        try queue.write { try $0.execute(sql: "INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, status, priority) VALUES ('T', '2026-10-26', '2026-10-26', 'u', 'task', 'Old', 'open', 'none')") }
        try Schema.migrator.migrate(queue)
        XCTAssertNil(try queue.read { try String.fetchOne($0, sql: "SELECT effort FROM items WHERE id = 'T'") })
    }

    func testEffortOnTasks() throws {
        let db = try StoreFactory.openInMemory()
        let h = CommandHandler(writer: db)
        guard case .ok(let r) = h.perform(.createTask(TaskDraft(title: "T", effort: .m)), writer: "u") else { return XCTFail() }
        XCTAssertEqual(try db.read { try TaskQueries.task($0, id: r.id!) }?.effort, .m)
        _ = h.perform(.updateTask(id: r.id!, TaskPatch(effort: .some(.l))), writer: "u")
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: "u") }, "Effort of “T”")
        XCTAssertEqual(try db.read { try TaskQueries.task($0, id: r.id!) }?.effort, .l)
        _ = h.perform(.updateTask(id: r.id!, TaskPatch(effort: .some(nil))), writer: "u")
        XCTAssertNil(try db.read { try TaskQueries.task($0, id: r.id!) }?.effort)
        // JSON round trip keeps "clear" distinct from "unchanged"
        let clear = try JSONDecoder().decode(TaskPatch.self, from: JSONEncoder().encode(TaskPatch(effort: .some(nil))))
        XCTAssertEqual(clear.effort, .some(nil))
        let unchanged = try JSONDecoder().decode(TaskPatch.self, from: JSONEncoder().encode(TaskPatch(title: "x")))
        XCTAssertNil(unchanged.effort)
    }
}
