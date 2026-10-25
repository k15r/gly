import GRDB
import XCTest
@testable import StoreSpike

final class SchemaTests: XCTestCase {
    func testMigratingEmptyDatabaseCreatesAllTablesAndViews() throws {
        let store = try Store()
        try store.migrate()
        try store.db.read { db in
            for table in syncedTables + ["change_log"] {
                XCTAssertTrue(try db.tableExists(table), "missing table \(table)")
            }
            for table in syncedTables {
                XCTAssertTrue(try db.viewExists("live_\(table)"), "missing view live_\(table)")
                // D2 columns on every synced table
                let cols = Set(try db.columns(in: table).map(\.name))
                for c in ["id", "created_at", "modified_at", "modified_by", "deleted_at"] {
                    XCTAssertTrue(cols.contains(c), "\(table) lacks \(c)")
                }
            }
        }
    }

    func testLiveViewsHideTombstones() throws {
        let store = try Store()
        try store.migrate()
        try store.db.write { db in
            let now = "2026-10-25 12:00:00.000"
            try db.execute(sql: """
                INSERT INTO tags (id, created_at, modified_at, modified_by, name) VALUES
                  ('t1', ?, ?, 'user@mac', 'person/alex'),
                  ('t2', ?, ?, 'user@mac', 'project/old')
                """, arguments: [now, now, now, now])
            try db.execute(sql: "UPDATE tags SET deleted_at = ? WHERE id = 't2'", arguments: [now])
        }
        try store.db.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags"), 2)
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT name FROM live_tags"), ["person/alex"])
        }
    }

    func testLiveTagNamesAreUniqueButTombstonesMayRepeat() throws {
        let store = try Store()
        try store.migrate()
        let now = "2026-10-25 12:00:00.000"
        try store.db.write { db in
            try db.execute(sql: "INSERT INTO tags (id, created_at, modified_at, modified_by, name, deleted_at) VALUES ('a', ?, ?, 'u', 'x', ?)", arguments: [now, now, now])
            try db.execute(sql: "INSERT INTO tags (id, created_at, modified_at, modified_by, name) VALUES ('b', ?, ?, 'u', 'x')", arguments: [now, now])
        }
        XCTAssertThrowsError(try store.db.write { db in
            try db.execute(sql: "INSERT INTO tags (id, created_at, modified_at, modified_by, name) VALUES ('c', ?, ?, 'u', 'x')", arguments: [now, now])
        })
    }

    func testCheckConstraintsRejectUnknownEnums() throws {
        let store = try Store()
        try store.migrate()
        let now = "2026-10-25 12:00:00.000"
        XCTAssertThrowsError(try store.db.write { db in
            try db.execute(sql: "INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, priority) VALUES ('i', ?, ?, 'u', 'task', 'T', 'critical')", arguments: [now, now])
        })
    }
}
