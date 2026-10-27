import GRDB
import XCTest
@testable import GlyCore

final class UndoRedoTests: XCTestCase {
    let me = "user@mac"
    var db: DatabaseQueue!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory() }

    func title(_ db: Database, _ id: String) throws -> String? { try String.fetchOne(db, sql: "SELECT title FROM live_items WHERE id = ?", arguments: [id]) }

    func testDeleteThenUndoRestoresTaskWithTags() throws {
        try db.write { db in
            let setup = Batch(db: db, writer: me)
            let item = try setup.insert("items", ["kind": "task", "title": "Prep 1:1", "priority": "high"])
            let tag = try setup.insert("tags", ["name": "person/alex", "name_key": "person/alex"])
            try setup.insert("item_tags", ["item_id": item, "tag_id": tag])
            try Batch(db: db, writer: me).softDelete("items", id: item)
            XCTAssertNil(try title(db, item))

            XCTAssertNotNil(try db.undo(writer: me))
            XCTAssertEqual(try title(db, item), "Prep 1:1")
            XCTAssertEqual(try String.fetchAll(db, sql: """
                SELECT t.name FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE it.item_id = ?
                """, arguments: [item]), ["person/alex"])
        }
    }

    func testEditOfTwoFieldsIsUndoneAsOneStep() throws {
        try db.write { db in
            let id = try Batch(db: db, writer: me).insert("items", ["kind": "task", "title": "Old", "due_day": "2026-10-27"])
            try Batch(db: db, writer: me).update("items", id: id, ["title": "New", "due_day": "2026-10-30"])
            try db.undo(writer: me)
            let row = try Row.fetchOne(db, sql: "SELECT title, due_day FROM items WHERE id = ?", arguments: [id])!
            XCTAssertEqual(row["title"] as String, "Old")
            XCTAssertEqual(row["due_day"] as String, "2026-10-27")
        }
    }

    func testRedoAfterUndoAndRedoChainAcrossSeveralSteps() throws {
        try db.write { db in
            let id = try Batch(db: db, writer: me).insert("items", ["kind": "task", "title": "v1"])
            try Batch(db: db, writer: me).update("items", id: id, ["title": "v2"])
            try Batch(db: db, writer: me).update("items", id: id, ["title": "v3"])
            try db.undo(writer: me); try db.undo(writer: me)
            XCTAssertEqual(try title(db, id), "v1")
            XCTAssertNotNil(try db.redo(writer: me))
            XCTAssertEqual(try title(db, id), "v2")
            XCTAssertNotNil(try db.redo(writer: me))
            XCTAssertEqual(try title(db, id), "v3")
            XCTAssertNil(try db.redo(writer: me), "nothing left to redo")
            // Undo after redo works like a normal undo.
            try db.undo(writer: me)
            XCTAssertEqual(try title(db, id), "v2")
        }
    }

    func testNewChangeClearsRedo() throws {
        try db.write { db in
            let id = try Batch(db: db, writer: me).insert("items", ["kind": "task", "title": "v1"])
            try Batch(db: db, writer: me).update("items", id: id, ["title": "v2"])
            try db.undo(writer: me)
            try Batch(db: db, writer: me).update("items", id: id, ["title": "other"])
            XCTAssertNil(try db.redo(writer: me))
            XCTAssertEqual(try title(db, id), "other")
        }
    }

    func testUndoOfCreateTombstones() throws {
        try db.write { db in
            let id = try Batch(db: db, writer: me).insert("items", ["kind": "task", "title": "T"])
            try db.undo(writer: me)
            XCTAssertNil(try title(db, id))
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items"), 1, "row kept as tombstone")
            try db.redo(writer: me)
            XCTAssertEqual(try title(db, id), "T", "redo brings it back")
        }
    }

    func testUndoNeverTouchesAnotherWritersBatch() throws {
        try db.write { db in
            let id = try Batch(db: db, writer: me).insert("items", ["kind": "task", "title": "mine"])
            try Batch(db: db, writer: "agent:mail").update("items", id: id, ["priority": "urgent"])
            try db.undo(writer: me)                 // reverts my insert, not the agent's update
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT priority FROM items WHERE id = ?", arguments: [id]), "urgent")
            XCTAssertNil(try db.undo(writer: me))
            XCTAssertNotNil(try db.undo(writer: "agent:mail"))
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT priority FROM items WHERE id = ?", arguments: [id]))
        }
    }
}
