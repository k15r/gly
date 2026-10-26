import GRDB
import XCTest
@testable import WorkDashCore

/// One editor save = one undo step, and undo/redo say what they revert.
final class UndoLabelTests: XCTestCase {
    let me = "user@mac"
    var db: DatabaseQueue!
    var handler: CommandHandler!
    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        handler = CommandHandler(writer: db)
    }

    @discardableResult
    func ok(_ c: Command, file: StaticString = #filePath, line: UInt = #line) -> CommandOK {
        switch handler.perform(c, writer: me) {
        case .ok(let r): return r
        case .failure(let f): XCTFail("unexpected failure \(f)", file: file, line: line); return CommandOK()
        }
    }
    func undoLabel() throws -> String? { try db.read { try $0.undoLabel(writer: me) } }
    func redoLabel() throws -> String? { try db.read { try $0.redoLabel(writer: me) } }

    func testEditWithTagsAndStatusIsOneUndoStep() throws {
        let id = ok(.createTask(TaskDraft(title: "Plan week", tags: ["person/alex"]))).id!
        ok(.updateTask(id: id, TaskPatch(title: "Plan next week", due: .some(Due(day: "2026-10-30")),
                                         tags: ["project/atlas"], status: .snoozed, snoozedUntil: "2026-10-28")))
        XCTAssertEqual(try undoLabel(), "Snooze “Plan next week”")
        XCTAssertEqual(ok(.undo).message, "Snooze “Plan week”")
        let r = try db.read { try Row.fetchOne($0, sql: "SELECT * FROM items WHERE id = ?", arguments: [id])! }
        XCTAssertEqual(r["title"] as String, "Plan week")
        XCTAssertNil(r["due_day"] as String?)
        XCTAssertEqual(r["status"] as String, "open")
        let tags = try db.read { try String.fetchAll($0, sql: "SELECT t.name FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE it.item_id = ?", arguments: [id]) }
        XCTAssertEqual(tags, ["person/alex"])
        XCTAssertEqual(try undoLabel(), "Create “Plan week”")
    }

    func testLabelsForEditDeleteAndTags() throws {
        let id = ok(.createTask(TaskDraft(title: "Old"))).id!
        ok(.updateTask(id: id, TaskPatch(title: "New", due: .some(Due(day: "2026-10-30", time: "09:00")))))
        XCTAssertEqual(try undoLabel(), "Edit “New” (title, due date)")
        ok(.setTags(id: id, ["project/atlas"]))
        XCTAssertEqual(try undoLabel(), "Edit “New” (tags)")
        ok(.setStatus(id: id, .done))
        XCTAssertEqual(try undoLabel(), "Complete “New”")
        ok(.deleteTask(id: id))
        XCTAssertEqual(try undoLabel(), "Delete “New”")
        XCTAssertNil(try redoLabel())
    }

    func testRedoLabelAndLabelAfterRedo() throws {
        let id = ok(.createTask(TaskDraft(title: "Old"))).id!
        ok(.updateTask(id: id, TaskPatch(title: "New")))
        ok(.undo)
        XCTAssertEqual(try redoLabel(), "Edit “Old” (title)")
        XCTAssertEqual(ok(.redo).message, "Edit “New” (title)")
        // After a redo, undo reverts that same change again and says so.
        XCTAssertEqual(try undoLabel(), "Edit “New” (title)")
        XCTAssertEqual(ok(.undo).message, "Edit “Old” (title)")
        XCTAssertEqual(ok(.undo).message, "Create “Old”")
        XCTAssertEqual(ok(.undo).message, "Nothing to undo.")
    }
}
