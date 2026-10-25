import GRDB
import XCTest
@testable import StoreSpike

final class ChangeLogTests: XCTestCase {
    var store: Store!
    let user = Writer("user@mac")
    let agent = Writer("agent:mail-triage")

    override func setUpWithError() throws {
        store = try Store()
        try store.migrate()
    }

    func testInsertLogsFields() throws {
        try store.db.write { db in
            let id = try db.insert("items", ["kind": "task", "title": "Approve budget", "priority": "high"], by: agent)
            let rows = try Row.fetchAll(db, sql: "SELECT op, field, writer FROM change_log WHERE row_id = ? ORDER BY field", arguments: [id])
            XCTAssertEqual(rows.map { $0["field"] as String }, ["id", "kind", "priority", "title"])
            XCTAssertTrue(rows.allSatisfy { ($0["op"] as String) == "insert" && ($0["writer"] as String) == "agent:mail-triage" })
        }
    }

    func testUpdateLogsOnlyChangedFieldsWithOldAndNew() throws {
        try store.db.write { db in
            let id = try db.insert("items", ["kind": "task", "title": "A", "priority": "low"], by: agent)
            try db.update("items", id: id, ["title": "A", "priority": "urgent"], by: user)
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM change_log WHERE op = 'update'")
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows[0]["field"] as String, "priority")
            XCTAssertEqual(decode(rows[0]["old_value"]), "low".databaseValue)
            XCTAssertEqual(decode(rows[0]["new_value"]), "urgent".databaseValue)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT modified_by FROM items WHERE id = ?", arguments: [id]), "user@mac")
        }
    }

    func testSoftDeleteTombstonesRowAndDependentsInOneBatch() throws {
        try store.db.write { db in
            let item = try db.insert("items", ["kind": "info", "title": "Notes"], by: user)
            let tag = try db.insert("tags", ["name": "person/alex"], by: user)
            try db.insert("item_tags", ["item_id": item, "tag_id": tag], by: user)
            try db.softDelete("items", id: item, by: user)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_item_tags"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items"), 1, "tombstone, not hard delete")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT batch) FROM change_log WHERE op = 'delete'"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_tags"), 1, "the tag itself survives")
        }
    }
}

final class UndoTests: XCTestCase {
    let user = Writer("user@mac")

    func testDeleteThenUndoRestoresItemWithTagsAndProperties() throws {
        let store = try Store()
        try store.migrate()
        try store.db.write { db in
            let item = try db.insert("items", ["kind": "task", "title": "Prep 1:1", "priority": "high"], by: user)
            let tag = try db.insert("tags", ["name": "person/alex"], by: user)
            try db.insert("item_tags", ["item_id": item, "tag_id": tag], by: user)
            let key = try db.insert("property_keys", ["name": "effort", "type": "number"], by: user)
            try db.insert("property_values", ["owner_id": item, "owner_kind": "item", "key_id": key, "number_value": 3.0], by: user)

            try db.softDelete("items", id: item, by: user)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items"), 0)

            XCTAssertNotNil(try db.undoLast(by: user))

            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT title FROM live_items WHERE id = ?", arguments: [item]), "Prep 1:1")
            XCTAssertEqual(try String.fetchAll(db, sql: """
                SELECT t.name FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE it.item_id = ?
                """, arguments: [item]), ["person/alex"])
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT number_value FROM live_property_values WHERE owner_id = ?", arguments: [item]), 3.0)

            // History keeps everything: the delete and the undo are both visible.
            let ops = try String.fetchAll(db, sql: "SELECT DISTINCT op FROM change_log WHERE row_id = ? ORDER BY op", arguments: [item])
            XCTAssertEqual(ops, ["delete", "insert", "undo"])
        }
    }

    func testUndoOfUpdateRestoresOldValueAndSecondUndoGoesFurtherBack() throws {
        let store = try Store()
        try store.migrate()
        try store.db.write { db in
            let item = try db.insert("items", ["kind": "task", "title": "A", "priority": "low"], by: user)
            try db.update("items", id: item, ["priority": "urgent"], by: user)
            try db.undoLast(by: user)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT priority FROM items WHERE id = ?", arguments: [item]), "low")
            // Next undo reverts the insert -> tombstone.
            try db.undoLast(by: user)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items"), 0)
            XCTAssertNil(try db.undoLast(by: user))
        }
    }
}
