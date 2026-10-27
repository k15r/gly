import GRDB
import XCTest
@testable import GlyCore

final class ChangeLogTests: XCTestCase {
    var db: DatabaseQueue!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory() }

    func testInsertLogsNonNullFieldsWithWriterAndBatch() throws {
        try db.write { db in
            let b = Batch(db: db, writer: "user@mac")
            let id = try b.insert("items", ["kind": "task", "title": "Approve budget", "priority": "high", "due_day": nil])
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM change_log WHERE row_id = ? ORDER BY field", arguments: [id])
            XCTAssertEqual(rows.map { $0["field"] as String }, ["id", "kind", "priority", "title"])
            XCTAssertTrue(rows.allSatisfy { ($0["writer"] as String) == "user@mac" && ($0["batch"] as String) == b.id && ($0["op"] as String) == "insert" })
            let item = try Row.fetchOne(db, sql: "SELECT modified_by, created_at FROM items WHERE id = ?", arguments: [id])!
            XCTAssertEqual(item["modified_by"] as String, "user@mac")
        }
    }

    func testUpdateWritesAndLogsOnlyChangedFields() throws {
        try db.write { db in
            let id = try Batch(db: db, writer: "user@mac").insert("items", ["kind": "task", "title": "A", "priority": "low"])
            let changed = try Batch(db: db, writer: "agent:x").update("items", id: id, ["title": "A", "priority": "urgent"])
            XCTAssertEqual(changed, ["priority"])
            let log = try Row.fetchOne(db, sql: "SELECT * FROM change_log WHERE op = 'update'")!
            XCTAssertEqual(ChangeValue.decode(log["old_value"]), "low".databaseValue)
            XCTAssertEqual(ChangeValue.decode(log["new_value"]), "urgent".databaseValue)
            XCTAssertEqual(log["writer"] as String, "agent:x")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT modified_by FROM items"), "agent:x")
        }
    }

    func testUpdateOfUnknownRowThrows() throws {
        XCTAssertThrowsError(try db.write { db in try Batch(db: db, writer: "u").update("items", id: "missing", ["title": "x"]) })
    }

    func testSoftDeleteTombstonesItemAndItsTagAssignmentsInOneBatch() throws {
        try db.write { db in
            let setup = Batch(db: db, writer: "user@mac")
            let item = try setup.insert("items", ["kind": "task", "title": "Prep"])
            let tag = try setup.insert("tags", ["name": "person/alex", "name_key": "person/alex"])
            try setup.insert("item_tags", ["item_id": item, "tag_id": tag])

            let del = Batch(db: db, writer: "user@mac")
            try del.softDelete("items", id: item)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_item_tags"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items"), 1, "tombstone, not hard delete")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_tags"), 1, "the tag itself survives")
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT DISTINCT batch FROM change_log WHERE op = 'delete'"), [del.id])
        }
    }

    func testChangeValueRoundTrip() {
        for v: DatabaseValue in [.null, 42.databaseValue, 1.5.databaseValue, "text with \"quotes\"".databaseValue, Data([1, 2, 3]).databaseValue] {
            XCTAssertEqual(ChangeValue.decode(ChangeValue.encode(v)), v)
        }
    }
}
