import GRDB
import XCTest
@testable import WorkDashCore

/// specs/info-pages, specs/links (resolution) and design P3/P6, through commands.
final class PageCommandTests: XCTestCase {
    let me = "user@mac"
    var db: DatabaseQueue!
    var h: CommandHandler!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    @discardableResult
    func ok(_ c: Command, writer: String? = nil, file: StaticString = #filePath, line: UInt = #line) -> CommandOK {
        switch h.perform(c, writer: writer ?? me) {
        case .ok(let r): return r
        case .failure(let f): XCTFail("unexpected failure \(f)", file: file, line: line); return CommandOK()
        }
    }
    func failure(_ c: Command) -> CommandFailure? { if case .failure(let f) = h.perform(c, writer: me) { return f }; return nil }
    func body(_ id: String) throws -> String { try db.read { try String.fetchOne($0, sql: "SELECT body FROM items WHERE id = ?", arguments: [id])! } }
    func row(_ id: String) throws -> Row { try db.read { try Row.fetchOne($0, sql: "SELECT * FROM items WHERE id = ?", arguments: [id])! } }
    func undoLabel() throws -> String? { try db.read { try $0.undoLabel(writer: me) } }

    // MARK: 2.1

    func testMinimalPage() throws {
        let id = ok(.createPage(PageDraft(title: "  Atlas architecture "))).id!
        let r = try row(id)
        XCTAssertEqual(r["kind"] as String, "info")
        XCTAssertEqual(r["title"] as String, "Atlas architecture")
        XCTAssertEqual(r["body"] as String, "")
        XCTAssertNil(r["status"] as String?)
        XCTAssertEqual(try undoLabel(), "Create page “Atlas architecture”")
    }

    func testEmptyTitle() {
        XCTAssertEqual(failure(.createPage(PageDraft(title: " ")))?.code, .validation)
        let id = ok(.createPage(PageDraft(title: "A"))).id!
        XCTAssertEqual(failure(.updatePage(id: id, PagePatch(title: "")))?.code, .validation)
    }

    func testPageCommandsRejectTasksAndViceVersa() {
        let task = ok(.createTask(TaskDraft(title: "T"))).id!
        let page = ok(.createPage(PageDraft(title: "P"))).id!
        XCTAssertEqual(failure(.updatePage(id: task, PagePatch(title: "x")))?.code, .notFound)
        XCTAssertEqual(failure(.updateTask(id: page, TaskPatch(title: "x")))?.code, .notFound)
    }

    func testUndoAPageDeletion() throws {
        let id = ok(.createPage(PageDraft(title: "Notes", body: "text", tags: ["project/atlas"]))).id!
        ok(.deletePage(id: id))
        XCTAssertEqual(try undoLabel(), "Delete page “Notes”")
        ok(.undo)
        let r = try row(id)
        XCTAssertNil(r["deleted_at"] as Date?)
        XCTAssertEqual(r["body"] as String, "text")
        let tags = try db.read { try String.fetchAll($0, sql: "SELECT t.name FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE it.item_id = ?", arguments: [id]) }
        XCTAssertEqual(tags, ["project/atlas"])
    }

    func testEditLabels() throws {
        let id = ok(.createPage(PageDraft(title: "Notes"))).id!
        ok(.updatePage(id: id, PagePatch(body: "new", tags: ["topic/x"])))
        XCTAssertEqual(try undoLabel(), "Edit page “Notes” (text, tags)")
    }

    func testDescribeAPersonCreatesTagWhenNeeded() throws {
        let r = ok(.updateTagPage(name: "person/alex", body: "Team lead"))
        XCTAssertEqual(try db.read { try String.fetchOne($0, sql: "SELECT page_body FROM tags WHERE id = ?", arguments: [r.id!]) }, "Team lead")
        XCTAssertEqual(try undoLabel(), "Edit tag page “person/alex”")
        let again = ok(.updateTagPage(name: "Person/Alex", body: "Team lead, atlas"))
        XCTAssertEqual(again.id, r.id, "existing tag reused (case-insensitive)")
    }

    func testCreateSubtag() throws {
        let r = ok(.createTag(name: "person/alex/goals"))
        XCTAssertEqual(try db.read { try String.fetchOne($0, sql: "SELECT name FROM tags WHERE id = ?", arguments: [r.id!]) }, "person/alex/goals")
        XCTAssertEqual(try undoLabel(), "Create tag “person/alex/goals”")
        let again = ok(.createTag(name: "Person/Alex/Goals"))
        XCTAssertEqual(again.id, r.id); XCTAssertFalse(again.changed)
        ok(.updateTagPage(name: "person/alex/goals", body: "kept"))
        ok(.createTag(name: "person/alex/goals"))
        XCTAssertEqual(try db.read { try String.fetchOne($0, sql: "SELECT page_body FROM tags WHERE id = ?", arguments: [r.id!]) }, "kept",
                       "creating an existing tag never touches its description")
        XCTAssertEqual(failure(.createTag(name: " / "))?.code, .validation)
    }

    // MARK: 2.2

    func testUniqueTitleResolves() throws {
        let page = ok(.createPage(PageDraft(title: "Atlas architecture"))).id!
        let task = ok(.createTask(TaskDraft(title: "T", body: "see [[atlas Architecture]]")))
        XCTAssertEqual(try body(task.id!), "see [Atlas architecture](workdash://item/\(page))")
        XCTAssertEqual(task.unresolved, [])
    }

    func testTagLinkResolves() throws {
        ok(.createTask(TaskDraft(title: "x", tags: ["person/alex"])))
        let tagID = try db.read { try String.fetchOne($0, sql: "SELECT id FROM tags") }!
        let t = ok(.createTask(TaskDraft(title: "y", body: "[[person/alex]]"))).id!
        XCTAssertEqual(try body(t), "[person/alex](workdash://tag/\(tagID))")
    }

    func testAmbiguousOrUnknownStaysMissing() throws {
        ok(.createTask(TaskDraft(title: "Dup")))
        ok(.createTask(TaskDraft(title: "Dup")))
        let r = ok(.createPage(PageDraft(title: "P", body: "[[Dup]] and [[Retro notes]]")))
        XCTAssertEqual(try body(r.id!), "[[Dup]] and [[Retro notes]]")
        XCTAssertEqual(r.unresolved, ["Dup", "Retro notes"])
    }

    func testCreateFromAMissingLinkRewritesAllSourcesInOneUndoStep() throws {
        let a = ok(.createTask(TaskDraft(title: "A", body: "x [[Retro notes]]"))).id!
        let b = ok(.createPage(PageDraft(title: "B", body: "[[retro notes]] y"))).id!
        let page = ok(.createPage(PageDraft(title: "Retro notes"))).id!
        XCTAssertEqual(try body(a), "x [Retro notes](workdash://item/\(page))")
        XCTAssertEqual(try body(b), "[Retro notes](workdash://item/\(page)) y")
        XCTAssertEqual(try undoLabel(), "Create page “Retro notes”")
        ok(.undo)
        XCTAssertEqual(try body(a), "x [[Retro notes]]")
        XCTAssertEqual(try body(b), "[[retro notes]] y")
    }

    func testTargetRenamedRefreshesLabels() throws {
        let page = ok(.createPage(PageDraft(title: "Atlas architecture"))).id!
        let t = ok(.createTask(TaskDraft(title: "T", body: "[[Atlas architecture]]"))).id!
        ok(.updatePage(id: page, PagePatch(title: "Atlas system design")))
        XCTAssertEqual(try body(t), "[Atlas system design](workdash://item/\(page))")
        XCTAssertEqual(try undoLabel(), "Edit page “Atlas system design” (title)")
    }

    // MARK: 2.3

    func testOneSessionIsOneUndoStep() throws {
        let id = ok(.createPage(PageDraft(title: "P", body: "v0"))).id!
        for v in ["v1", "v2", "v3"] { ok(.updatePage(id: id, PagePatch(body: v, session: "s1"))) }
        let batches = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT batch) FROM change_log WHERE row_id = ? AND field = 'body'", arguments: [id]) }
        XCTAssertEqual(batches, 2, "create + one session")
        ok(.undo)
        XCTAssertEqual(try body(id), "v0")
        ok(.redo)
        XCTAssertEqual(try body(id), "v3")
    }

    func testDifferentSessionOrWriterIsNotMerged() throws {
        let id = ok(.createPage(PageDraft(title: "P", body: "v0"))).id!
        ok(.updatePage(id: id, PagePatch(body: "v1", session: "s1")))
        ok(.updatePage(id: id, PagePatch(body: "v2", session: "s2")))
        ok(.undo)
        XCTAssertEqual(try body(id), "v1", "s2 was its own step")

        let task = ok(.createTask(TaskDraft(title: "T"))).id!
        ok(.updateTask(id: task, TaskPatch(body: "mine", session: "s3")))
        ok(.updateTask(id: task, TaskPatch(body: "agent"), ), writer: "agent:x@mac")
        ok(.updateTask(id: task, TaskPatch(body: "mine again", session: "s3")))
        let mine = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT batch) FROM change_log WHERE row_id = ? AND field = 'body' AND writer = ?", arguments: [task, self.me]) }
        XCTAssertEqual(mine, 2, "another writer's change in between ends the coalescing")
    }
}
