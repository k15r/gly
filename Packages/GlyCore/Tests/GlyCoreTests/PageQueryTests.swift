import GRDB
import XCTest
@testable import GlyCore

/// specs/info-pages (list), specs/links (backlinks, deleted targets), specs/tag-pages, specs/tags (page-only tags).
final class PageQueryTests: XCTestCase {
    var db: DatabaseQueue!
    var h: CommandHandler!
    let today = LocalDay("2026-10-26")!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    @discardableResult
    func make(_ c: Command, at date: Date = Date()) -> String {
        guard case .ok(let r) = h.perform(c, writer: "u", now: date) else { XCTFail("\(c)"); return "" }
        return r.id ?? ""
    }

    func testRecentlyChangedFirst() throws {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let older = make(.createPage(PageDraft(title: "Older")), at: t0)
        make(.createPage(PageDraft(title: "Newer")), at: t0.addingTimeInterval(60))
        XCTAssertEqual(try db.read { try PageQueries.list($0) }.map(\.title), ["Newer", "Older"])
        make(.updatePage(id: older, PagePatch(body: "edit")), at: t0.addingTimeInterval(120))
        XCTAssertEqual(try db.read { try PageQueries.list($0) }.map(\.title), ["Older", "Newer"])
    }

    func testFilterByTagIncludesDescendants() throws {
        make(.createPage(PageDraft(title: "A", tags: ["project/atlas"])))
        make(.createPage(PageDraft(title: "B", tags: ["project"])))
        make(.createPage(PageDraft(title: "C", tags: ["person/alex"])))
        let titles = try db.read { try PageQueries.list($0, tag: try TagName("project")) }.map(\.title).sorted()
        XCTAssertEqual(titles, ["A", "B"])
    }

    func testBacklinksOnAPage() throws {
        let target = make(.createPage(PageDraft(title: "Atlas architecture")))
        make(.createTask(TaskDraft(title: "Task one", body: "Prep: read [[Atlas architecture]] first")))
        make(.createTask(TaskDraft(title: "Task two", body: "[[Atlas architecture]] and again [[Atlas architecture]]")))
        make(.createPage(PageDraft(title: "Overview", body: "Start here.\nDetails in [[Atlas architecture]].")))
        let deleted = make(.createPage(PageDraft(title: "Gone", body: "[[Atlas architecture]]")))
        make(.deletePage(id: deleted))
        let backlinks = try db.read { try LinkQueries.backlinks($0, to: target) }
        XCTAssertEqual(backlinks.map(\.source.title), ["Overview", "Task one", "Task two"], "deleted sources are hidden, one entry per source")
        XCTAssertEqual(backlinks.first { $0.source.title == "Task one" }?.excerpt, "Prep: read Atlas architecture first")
        XCTAssertEqual(backlinks.first { $0.source.title == "Overview" }?.excerpt, "Details in Atlas architecture.")
    }

    func testBacklinksToATag() throws {
        let page = make(.createPage(PageDraft(title: "P", tags: ["person/alex"])))
        let tagID = try db.read { try String.fetchOne($0, sql: "SELECT id FROM tags WHERE name_key = 'person/alex'") }!
        make(.updatePage(id: page, PagePatch(body: "about [[person/alex]]")))
        XCTAssertEqual(try db.read { try LinkQueries.backlinks($0, to: tagID, isTag: true) }.map(\.source.title), ["P"])
    }

    func testLinkedTaskDeletedShowsDeletedTarget() throws {
        let task = make(.createTask(TaskDraft(title: "Linked task")))
        let page = make(.createPage(PageDraft(title: "P", body: "see [[Linked task]] and [[Nowhere]]")))
        make(.deleteTask(id: task))
        let links = try db.read { try LinkQueries.outgoing($0, sourceTable: "items", sourceID: page) }
        XCTAssertEqual(links.map(\.target), [.deleted(LinkRef(kind: .task, id: task, title: "Linked task")), .missing("Nowhere")])
    }

    func testProjectTagPage() throws {
        make(.createTask(TaskDraft(title: "Open one", priority: .high, tags: ["project/atlas"])))
        make(.createTask(TaskDraft(title: "Open two", tags: ["project/atlas/logs"])))
        let done = make(.createTask(TaskDraft(title: "Done one", tags: ["project/atlas"])))
        _ = h.perform(.setStatus(id: done, .done), writer: "u")
        make(.createPage(PageDraft(title: "Log notes", tags: ["project/atlas/logs"])))
        make(.updateTagPage(name: "project/atlas", body: "The atlas project"))
        let page = try db.read { try TagPageQueries.page($0, name: try TagName("project/atlas"), today: self.today) }
        XCTAssertEqual(page.body, "The atlas project")
        XCTAssertEqual(page.openTasks.map(\.title), ["Open one", "Open two"])
        XCTAssertEqual(page.pages.map(\.title), ["Log notes"])
        XCTAssertEqual(page.finishedTasks.map(\.title), ["Done one"])
    }

    func testGroupTagPage() throws {
        make(.createTask(TaskDraft(title: "A", tags: ["person/alex"])))
        make(.createPage(PageDraft(title: "S", tags: ["person/sam"])))
        let page = try db.read { try TagPageQueries.page($0, name: try TagName("person"), today: self.today) }
        XCTAssertNil(page.tagID, "group node without a tag row yet")
        XCTAssertEqual(page.openTasks.map(\.title), ["A"])
        XCTAssertEqual(page.pages.map(\.title), ["S"])
    }

    func testTagUsedOnlyOnPages() throws {
        make(.createPage(PageDraft(title: "Sec notes", tags: ["topic/security"])))
        make(.createTask(TaskDraft(title: "T", tags: ["person/alex"])))
        let tree = try db.read { try TagQueries.tagTree($0, today: "2026-10-26") }
        let topic = tree.first { $0.path == "topic" }
        XCTAssertEqual(topic?.children.first?.path, "topic/security")
        XCTAssertEqual(topic?.children.first?.openCount, 0)
        XCTAssertEqual(tree.first { $0.path == "person" }?.openCount, 1)
    }
}

extension PageQueryTests {
    func testItemsAsLeavesOfTheTree() throws {
        make(.createTask(TaskDraft(title: "child task", tags: ["project/atlas/logs"])))
        make(.createPage(PageDraft(title: "B page", tags: ["project/atlas"])))
        make(.createPage(PageDraft(title: "A page", tags: ["project/atlas"])))
        make(.createTask(TaskDraft(title: "Normal task", priority: .normal, tags: ["project/atlas"])))
        make(.createTask(TaskDraft(title: "Urgent task", priority: .urgent, tags: ["project/atlas"])))
        let snoozed = make(.createTask(TaskDraft(title: "Snoozed task", tags: ["project/atlas"])))
        _ = h.perform(.setStatus(id: snoozed, .snoozed, snoozedUntil: "2026-11-30"), writer: "u")
        let done = make(.createTask(TaskDraft(title: "Done task", tags: ["project/atlas"])))
        _ = h.perform(.setStatus(id: done, .done), writer: "u")
        let tree = try db.read { try TagQueries.tagTree($0, today: "2026-10-26") }
        let atlas = tree.first { $0.path == "project" }?.children.first { $0.path == "project/atlas" }
        XCTAssertEqual(atlas?.items.map(\.title), ["Urgent task", "Normal task", "Snoozed task", "A page", "B page"],
                       "open tasks in task-list order, then pages; no done task")
        XCTAssertEqual(atlas?.items.map(\.kind), [.task, .task, .task, .page, .page])
        XCTAssertEqual(atlas?.items.first { $0.title == "Snoozed task" }?.snoozed, true)
        XCTAssertEqual(atlas?.children.map(\.path), ["project/atlas/logs"], "child tags stay children")
        XCTAssertEqual(tree.first { $0.path == "project" }?.items, [], "not repeated on the parent")
    }

    func testItemWithTwoTags() throws {
        let id = make(.createPage(PageDraft(title: "Shared", tags: ["project/atlas", "project/beta"])))
        let project = try db.read { try TagQueries.tagTree($0, today: "2026-10-26") }.first { $0.path == "project" }
        let atlas = project?.children.first { $0.path == "project/atlas" }
        let beta = project?.children.first { $0.path == "project/beta" }
        XCTAssertEqual(atlas?.items, [TreeLeaf(kind: .page, id: id, title: "Shared", otherTags: ["project/beta"])])
        XCTAssertEqual(beta?.items.first?.otherTags, ["project/atlas"])
        XCTAssertEqual(project?.items, [])
    }

    func testUntaggedItems() throws {
        make(.createPage(PageDraft(title: "Loose page")))
        make(.createTask(TaskDraft(title: "Loose task")))
        make(.createPage(PageDraft(title: "Tagged", tags: ["a"])))
        let deleted = make(.createPage(PageDraft(title: "Gone")))
        make(.deletePage(id: deleted))
        let done = make(.createTask(TaskDraft(title: "Done loose")))
        _ = h.perform(.setStatus(id: done, .done), writer: "u")
        XCTAssertEqual(try db.read { try TagQueries.untaggedItems($0) }.map(\.title), ["Loose task", "Loose page"])
    }
}

extension PageQueryTests {
    /// Found in manual check B7: a tag whose only task is snoozed vanished from the tree, and counts differed from the tag page.
    func testSnoozedTasksCountInTheTagTree() throws {
        make(.createTask(TaskDraft(title: "open", tags: ["person/alex"])))
        let snoozed = make(.createTask(TaskDraft(title: "snoozed", tags: ["person/alex", "person/sam"])))
        _ = h.perform(.setStatus(id: snoozed, .snoozed, snoozedUntil: "2026-11-30"), writer: "u")
        let person = try db.read { try TagQueries.tagTree($0, today: "2026-10-26") }.first { $0.path == "person" }
        XCTAssertEqual(person?.openCount, 2)
        XCTAssertEqual(person?.children.map(\.path), ["person/alex", "person/sam"])
        XCTAssertEqual(person?.children.first { $0.path == "person/sam" }?.openCount, 1)
        let tagPage = try db.read { try TagPageQueries.page($0, name: try TagName("person"), today: self.today) }
        XCTAssertEqual(tagPage.openTasks.count, person?.openCount, "tree count matches the tag page")
    }
}
