import GRDB
import XCTest
@testable import WorkDashCore

final class SchemaTests: XCTestCase {
    let now = "2026-10-27 12:00:00.000"

    func testMigrationCreatesTablesViewsAndSyncColumns() throws {
        let db = try StoreFactory.openInMemory()
        try db.read { db in
            for table in Schema.syncedTables + ["change_log"] {
                XCTAssertTrue(try db.tableExists(table), table)
            }
            for table in Schema.syncedTables {
                XCTAssertTrue(try db.viewExists("live_\(table)"), "live_\(table)")
                let columns = Set(try db.columns(in: table).map(\.name))
                for c in ["id", "created_at", "modified_at", "modified_by", "deleted_at"] {
                    XCTAssertTrue(columns.contains(c), "\(table).\(c)")
                }
            }
            XCTAssertTrue(try db.columns(in: "change_log").map(\.name).contains("redo_of"))
        }
    }

    func testUnknownEnumValuesAreRejected() throws {
        let db = try StoreFactory.openInMemory()
        for (column, value) in [("kind", "note"), ("status", "inbox_x"), ("priority", "critical")] {
            XCTAssertThrowsError(try db.write { db in
                var row: [String: DatabaseValueConvertible] = ["id": UUID().uuidString, "created_at": now, "modified_at": now,
                                                              "modified_by": "u", "kind": "task", "title": "T"]
                row[column] = value
                let cols = row.keys.sorted()
                try db.execute(sql: "INSERT INTO items (\(cols.joined(separator: ","))) VALUES (\(cols.map { _ in "?" }.joined(separator: ",")))",
                               arguments: StatementArguments(cols.map { row[$0] }))
            }, "\(column)=\(value) must be rejected")
        }
    }

    func testEmptyTitleIsRejected() throws {
        let db = try StoreFactory.openInMemory()
        XCTAssertThrowsError(try db.write { db in
            try db.execute(sql: "INSERT INTO items (id, created_at, modified_at, modified_by, kind, title) VALUES ('i', ?, ?, 'u', 'task', '')",
                           arguments: [now, now])
        })
    }

    func testTagNameKeyIsUniqueAmongLiveTagsOnly() throws {
        let db = try StoreFactory.openInMemory()
        try db.write { db in
            try db.execute(sql: "INSERT INTO tags (id, created_at, modified_at, modified_by, name, name_key, deleted_at) VALUES ('a', ?, ?, 'u', 'X', 'x', ?)", arguments: [now, now, now])
            try db.execute(sql: "INSERT INTO tags (id, created_at, modified_at, modified_by, name, name_key) VALUES ('b', ?, ?, 'u', 'x', 'x')", arguments: [now, now])
        }
        XCTAssertThrowsError(try db.write { db in
            try db.execute(sql: "INSERT INTO tags (id, created_at, modified_at, modified_by, name, name_key) VALUES ('c', ?, ?, 'u', 'X', 'x')", arguments: [now, now])
        })
    }

    func testLiveViewsHideTombstones() throws {
        let db = try StoreFactory.openInMemory()
        try db.write { db in
            try db.execute(sql: "INSERT INTO items (id, created_at, modified_at, modified_by, kind, title) VALUES ('a', ?, ?, 'u', 'task', 'A'), ('b', ?, ?, 'u', 'task', 'B')",
                           arguments: [now, now, now, now])
            try db.execute(sql: "UPDATE items SET deleted_at = ? WHERE id = 'b'", arguments: [now])
        }
        try db.read { db in
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT id FROM live_items"), ["a"])
        }
    }
}
