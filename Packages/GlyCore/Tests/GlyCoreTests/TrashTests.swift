import GRDB
import XCTest
@testable import GlyCore

/// specs/trash and design T1–T3.
final class TrashTests: XCTestCase {
    let me = "user@mac-test01"
    let claude = "agent:claude-code@mac-test01"
    var db: DatabaseQueue!
    var h: CommandHandler!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    @discardableResult
    func ok(_ c: Command, as writer: String? = nil) -> CommandOK {
        guard case .ok(let r) = h.perform(c, writer: writer ?? me) else { XCTFail("\(c)"); return CommandOK() }
        return r
    }
    func trash(since: Date? = nil) throws -> [TrashEntry] { try db.read { try TrashQueries.list($0, since: since) } }

    // MARK: 1.1

    func testAgentDeletesAPage() throws {
        let id = ok(.createPage(PageDraft(title: "Goals", body: "# Goals\nShip the **thing**", tags: ["person/bob"]))).id!
        ok(.deletePage(id: id), as: claude)
        let entry = try XCTUnwrap(try trash().first)
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.kind, .page)
        XCTAssertEqual(entry.title, "Goals")
        XCTAssertEqual(entry.tags, ["person/bob"], "the tags it had when deleted")
        XCTAssertEqual(entry.excerpt, "Goals Ship the thing")
        XCTAssertEqual(WriterName.display(entry.deletedBy), "Claude Code")
        XCTAssertNotNil(entry.batch)
    }

    func testNewestFirstAcrossKindsAndWriters() throws {
        let task = ok(.createTask(TaskDraft(title: "Call the venue", tags: ["project/atlas"]))).id!
        let page = ok(.createPage(PageDraft(title: "Notes"))).id!
        try db.write { db in try Batch(db: db, writer: me, at: Date().addingTimeInterval(-3600)).softDelete("items", id: task) }
        ok(.deletePage(id: page), as: "agent:joule@mac-test01")
        let entries = try trash()
        XCTAssertEqual(entries.map(\.id), [page, task])
        XCTAssertEqual(entries.map { WriterName.display($0.deletedBy) }, ["Joule", "you"])
        XCTAssertEqual(entries[1].status, .open)
        XCTAssertEqual(entries[1].tags, ["project/atlas"])
    }

    func testOlderDeletes() throws {
        let old = ok(.createTask(TaskDraft(title: "Old"))).id!
        let recent = ok(.createPage(PageDraft(title: "Recent"))).id!
        let now = Date()
        try db.write { db in try Batch(db: db, writer: me, at: now.addingTimeInterval(-40 * 86400)).softDelete("items", id: old) }
        try db.write { db in try Batch(db: db, writer: me, at: now.addingTimeInterval(-86400)).softDelete("items", id: recent) }
        let cutoff = now.addingTimeInterval(-Double(TrashQueries.defaultDays) * 86400)
        XCTAssertEqual(try trash(since: cutoff).map(\.id), [recent])
        XCTAssertEqual(try db.read { try TrashQueries.count($0, before: cutoff) }, 1)
        XCTAssertEqual(try trash().map(\.id), [recent, old])
    }

    func testLiveAndUndoneDeletesAreNotInTheTrash() throws {
        let id = ok(.createPage(PageDraft(title: "Kept"))).id!
        XCTAssertEqual(try trash(), [])
        ok(.deletePage(id: id))
        try db.write { db in _ = try db.undo(writer: me) }
        XCTAssertEqual(try trash(), [], "the delete was undone")
        try db.write { db in _ = try db.redo(writer: me) }
        XCTAssertEqual(try trash().first?.id, id, "redone delete: in the trash again")
        XCTAssertNotNil(try trash().first?.batch)
    }

    func testItemWithoutDeleteEntryIsStillListed() throws {
        let id = ok(.createPage(PageDraft(title: "Legacy"))).id!
        try db.write { db in try db.execute(sql: "UPDATE items SET deleted_at = ? WHERE id = ?", arguments: [Date(), id]) }
        let entry = try XCTUnwrap(try trash().first)
        XCTAssertNil(entry.deletedBy)
        XCTAssertNil(entry.batch)
        XCTAssertEqual(WriterName.display(entry.deletedBy), "unknown")
    }

    func testWriterNames() {
        XCTAssertEqual(WriterName.display("user@mac-1"), "you")
        XCTAssertEqual(WriterName.display("system@mac-1"), "gly")
        XCTAssertEqual(WriterName.display("agent:claude-code@mac-1"), "Claude Code")
        XCTAssertEqual(WriterName.display("agent:joule-desktop@mac-1"), "Joule Desktop")
    }

    // MARK: 1.2

    func failure(_ c: Command) -> CommandFailure? { if case .failure(let f) = h.perform(c, writer: me) { return f }; return nil }
    func liveTags(_ id: String) throws -> [String] {
        try db.read { try String.fetchAll($0, sql: "SELECT t.name FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE it.item_id = ? ORDER BY t.name_key", arguments: [id]) }
    }

    func testRestoreAnAgentsDelete() throws {
        let task = ok(.createTask(TaskDraft(title: "Call the venue", due: Due(day: "2026-11-02"), tags: ["project/atlas"]))).id!
        let page = ok(.createPage(PageDraft(title: "Plan", body: "see [Call the venue](gly://item/\(task))"))).id!
        ok(.deleteTask(id: task), as: "agent:joule@mac-test01")
        XCTAssertEqual(try db.read { try LinkQueries.reference($0, id: task, isTag: false)?.1 }, true, "link target deleted")

        ok(.restore(id: task))
        let row = try XCTUnwrap(try db.read { try Row.fetchOne($0, sql: "SELECT * FROM live_items WHERE id = ?", arguments: [task]) })
        XCTAssertEqual(row["status"] as String, "open")
        XCTAssertEqual(row["due_day"] as String, "2026-11-02")
        XCTAssertEqual(try liveTags(task), ["project/atlas"])
        XCTAssertEqual(try trash(), [], "left the trash")
        XCTAssertEqual(try db.read { try LinkQueries.reference($0, id: task, isTag: false)?.1 }, false, "links work again")
        XCTAssertEqual(try db.read { try LinkQueries.backlinks($0, to: task, isTag: false) }.map(\.source.id), [page])
        XCTAssertEqual(try db.read { try SearchQueries.search($0, "venue") }.tasks.map(\.ref.id), [task])
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Restore “Call the venue”")
    }

    func testUndoARestore() throws {
        let page = ok(.createPage(PageDraft(title: "Goals", tags: ["person/bob"]))).id!
        ok(.deletePage(id: page), as: claude)
        ok(.restore(id: page))
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Restore page “Goals”")
        try db.write { db in _ = try db.undo(writer: me) }
        XCTAssertEqual(try trash().map(\.id), [page], "deleted again and back in the trash")
        XCTAssertEqual(try trash().first?.tags, ["person/bob"])
        try db.write { db in _ = try db.redo(writer: me) }
        XCTAssertEqual(try trash(), [])
        XCTAssertEqual(try liveTags(page), ["person/bob"])
    }

    func testDeleteAndRestoreLater() throws {
        let task = ok(.createTask(TaskDraft(title: "A", tags: ["x"]))).id!
        let other = ok(.createTask(TaskDraft(title: "B"))).id!
        ok(.deleteTask(id: task))
        ok(.updateTask(id: other, TaskPatch(title: "B2")))
        ok(.restore(id: task))
        XCTAssertEqual(try db.read { try String.fetchOne($0, sql: "SELECT title FROM live_items WHERE id = ?", arguments: [other]) }, "B2", "other changes stay")
        XCTAssertEqual(try liveTags(task), ["x"])
    }

    func testTagsRemovedBeforeTheDeleteStayRemoved() throws {
        let task = ok(.createTask(TaskDraft(title: "A", tags: ["keep", "drop"]))).id!
        ok(.updateTask(id: task, TaskPatch(tags: ["keep"])))
        ok(.deleteTask(id: task))
        XCTAssertEqual(try trash().first?.tags, ["keep"])
        ok(.restore(id: task))
        XCTAssertEqual(try liveTags(task), ["keep"])
    }

    func testRestoreNotInTrash() throws {
        let live = ok(.createPage(PageDraft(title: "Live"))).id!
        XCTAssertEqual(failure(.restore(id: live))?.code, .notFound)
        XCTAssertEqual(failure(.restore(id: "nope"))?.code, .notFound)
        XCTAssertTrue(failure(.restore(id: live))?.message.contains("not in the trash") ?? false)
    }

    func testRestoreLegacyDeleteWithoutHistory() throws {
        let id = ok(.createPage(PageDraft(title: "Legacy"))).id!
        try db.write { db in try db.execute(sql: "UPDATE items SET deleted_at = ? WHERE id = ?", arguments: [Date(), id]) }
        ok(.restore(id: id))
        XCTAssertEqual(try trash(), [])
    }

    // MARK: Erase all data (Settings → Data)

    func testEraseAllData() throws {
        let page = ok(.createPage(PageDraft(title: "Goals", body: "see [[Call]]", tags: ["person/bob"]))).id!
        let task = ok(.createTask(TaskDraft(title: "Call", tags: ["project/atlas"]))).id!
        ok(.deletePage(id: page), as: claude)
        ok(.updateTagPage(name: "person", body: "people"))
        ok(.eraseAllData)
        for table in Schema.syncedTables + ["change_log", "link_index", "search_index"] {
            XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") }, 0, table)
        }
        XCTAssertEqual(try trash(), [])
        XCTAssertNil(try db.read { try $0.undoLabel(writer: me) }, "nothing to undo")
        XCTAssertEqual(failure(.restore(id: task))?.code, .notFound)
        // gly keeps working on the empty store.
        let fresh = ok(.createTask(TaskDraft(title: "Fresh", tags: ["x"]))).id!
        XCTAssertEqual(try liveTags(fresh), ["x"])
        XCTAssertEqual(try db.read { try SearchQueries.search($0, "fresh") }.tasks.map(\.ref.id), [fresh])
    }
}
