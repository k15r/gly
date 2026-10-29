import GRDB
import XCTest
@testable import GlyCore

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

extension SchemaTests {
    func testV1DatabaseMigratesAndBackfills() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue, upTo: "v1")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, body, status, priority)
                VALUES ('T1', '2026-10-26', '2026-10-26', 'u', 'task', 'Old task', 'see [[Atlas]]', 'open', 'none')
                """)
        }
        try Schema.migrator.migrate(queue)
        try queue.read { db in
            XCTAssertTrue(try db.tableExists("link_index"))
            XCTAssertTrue(try db.tableExists("search_index"))
            XCTAssertTrue(try db.columns(in: "change_log").contains { $0.name == "session" })
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT missing_title FROM link_index WHERE source_id = 'T1'"), "Atlas")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM search_index WHERE search_index MATCH 'old'"), 1)
        }
        XCTAssertFalse(Schema.syncedTables.contains("link_index"))
        XCTAssertFalse(Schema.syncedTables.contains("search_index"))
    }

    /// bookmarks B1: v9 rebuilds `items` with `bookmark` in the kind check; rows, references and indexes survive.
    func testV9RebuildKeepsAPopulatedDatabase() throws {
        var config = Configuration(); config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        try Schema.migrator.migrate(queue, upTo: "v8")
        try queue.write { db in
            let cols = "id, created_at, modified_at, modified_by"
            try db.execute(sql: """
                INSERT INTO items (\(cols), kind, title, body, status, priority, due_day, snooze_ended_on)
                VALUES ('T1', ?, ?, 'u', 'task', 'Draft report', 'see [[Atlas]]', 'open', 'high', '2026-11-02', '2026-10-26');
                INSERT INTO items (\(cols), kind, title, body) VALUES ('P1', ?, ?, 'u', 'info', 'Atlas', 'notes about apples');
                INSERT INTO items (\(cols), kind, title, body, deleted_at) VALUES ('P2', ?, ?, 'u', 'info', 'Gone', '', ?);
                INSERT INTO items (\(cols), kind, title, event_key) VALUES ('N1', ?, ?, 'u', 'event_note', 'Weekly', 'k1');
                INSERT INTO tags (\(cols), name, name_key) VALUES ('G1', ?, ?, 'u', 'Work', 'work');
                INSERT INTO item_tags (\(cols), item_id, tag_id) VALUES ('IT1', ?, ?, 'u', 'T1', 'G1');
                INSERT INTO task_work (\(cols), item_id, day, minutes, kind) VALUES ('W1', ?, ?, 'u', 'T1', '2026-10-27', 60, 'part');
                """, arguments: StatementArguments(Array(repeating: now, count: 15)))
            try DerivedIndex.rebuild(db)
        }
        try Schema.migrator.migrate(queue)
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items"), 4)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items"), 3)
            let task = try Row.fetchOne(db, sql: "SELECT * FROM items WHERE id = 'T1'")!
            XCTAssertEqual(task["priority"] as String?, "high")
            XCTAssertEqual(task["snooze_ended_on"] as String?, "2026-10-26")
            XCTAssertNil(task["url"] as String?)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_item_tags WHERE item_id = 'T1'"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_task_work WHERE item_id = 'T1'"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM link_index WHERE source_id = 'T1'"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM search_index WHERE search_index MATCH 'apples'"), 1)
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            let indexes = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'items'"))
            for name in ["items_kind_status", "items_due_day", "items_event_key", "items_event_start", "items_series_rule", "items_bookmark_url"] {
                XCTAssertTrue(indexes.contains(name), name)
            }
        }
        // The new kind is accepted, the old check still rejects unknown kinds, and a live URL is bookmarked once.
        let insert = "INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, url) VALUES (?, ?, ?, 'u', ?, 'Docs', ?)"
        try queue.write { db in try db.execute(sql: insert, arguments: ["B1", now, now, "bookmark", "https://example.com/docs"]) }
        XCTAssertThrowsError(try queue.write { db in try db.execute(sql: insert, arguments: ["B2", now, now, "bookmark", "https://example.com/docs"]) })
        XCTAssertThrowsError(try queue.write { db in try db.execute(sql: insert, arguments: ["X1", now, now, "note", nil]) })
        try queue.write { db in
            try db.execute(sql: "UPDATE items SET deleted_at = ? WHERE id = 'B1'", arguments: [now])
            try db.execute(sql: insert, arguments: ["B3", now, now, "bookmark", "https://example.com/docs"])
        }
    }

    /// Rollback check (design Migration Plan): what an older build's migrator does with a v2 database.
    func testOlderMigratorOnV2Database() throws {
        let queue = try StoreFactory.openInMemory()
        var old = DatabaseMigrator()
        old.registerMigration("v1") { _ in XCTFail("v1 must not run again") }
        XCTAssertNoThrow(try old.migrate(queue), "an older migrator accepts the unknown applied migration v2")
        try queue.read { db in XCTAssertTrue(try old.hasBeenSuperseded(db)) }
    }
}
