import GRDB
import XCTest
@testable import GlyCore

/// specs/links "Links typed as text" (prefixes, tag paths, candidates).
final class LinkDisambiguationTests: XCTestCase {
    var db: DatabaseQueue!
    var h: CommandHandler!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    @discardableResult
    func ok(_ c: Command) -> CommandOK {
        guard case .ok(let r) = h.perform(c, writer: "u") else { XCTFail("\(c)"); return CommandOK() }
        return r
    }
    func body(_ id: String) throws -> String { try db.read { try String.fetchOne($0, sql: "SELECT body FROM items WHERE id = ?", arguments: [id])! } }

    func testTagPathPicksThePageWithThatTag() throws {
        let alex = ok(.createPage(PageDraft(title: "Goals", tags: ["person/alex"]))).id!
        ok(.createPage(PageDraft(title: "Goals", tags: ["person/sam"])))
        let t = ok(.createTask(TaskDraft(title: "T", body: "see [[person/alex/Goals]]")))
        XCTAssertEqual(try body(t.id!), "see [Goals](gly://item/\(alex))")
        XCTAssertEqual(t.unresolved, [])
    }

    func testAmbiguousTitleReturnsCandidates() throws {
        ok(.createPage(PageDraft(title: "Goals", tags: ["person/alex"])))
        ok(.createPage(PageDraft(title: "Goals", tags: ["person/sam"])))
        let r = ok(.createTask(TaskDraft(title: "T", body: "[[Goals]]")))
        XCTAssertEqual(r.unresolved, ["Goals"])
        XCTAssertEqual(r.unresolvedLinks?.first?.candidates.map { $0.tags }.sorted { $0[0] < $1[0] }, [["person/alex"], ["person/sam"]])
        XCTAssertEqual(r.unresolvedLinks?.first?.candidates.count, 2)
        // A tag path that is still ambiguous (both below `person`) offers both too.
        let p = ok(.createTask(TaskDraft(title: "T2", body: "[[person/Goals]]")))
        XCTAssertEqual(p.unresolvedLinks?.first?.candidates.count, 2)
    }

    func testKindPrefix() throws {
        ok(.createPage(PageDraft(title: "Offsite")))
        let task = ok(.createTask(TaskDraft(title: "Offsite"))).id!
        let page = ok(.createPage(PageDraft(title: "P", body: "[[Offsite]] and [[task:Offsite]]")))
        XCTAssertEqual(page.unresolvedLinks?.first?.candidates.count, 2, "bare title is ambiguous across kinds")
        XCTAssertTrue(try body(page.id!).hasSuffix("[Offsite](gly://item/\(task))"))
        ok(.createPage(PageDraft(title: "Q", tags: ["project/atlas"])))
        let q = ok(.createPage(PageDraft(title: "R", body: "[[tag:project/atlas]]")))
        XCTAssertTrue(try body(q.id!).contains("gly://tag/"))
    }

    func testResolvedOnceSurvivesTagChanges() throws {
        let alex = ok(.createPage(PageDraft(title: "Goals", tags: ["person/alex"]))).id!
        ok(.createPage(PageDraft(title: "Goals", tags: ["person/sam"])))
        let t = ok(.createTask(TaskDraft(title: "T", body: "[[person/alex/Goals]]"))).id!
        ok(.updatePage(id: alex, PagePatch(tags: ["person/kim"])))
        XCTAssertEqual(try body(t), "[Goals](gly://item/\(alex))")
    }

    func testTitleContainingSlashStillMatchesExactly() throws {
        let p = ok(.createPage(PageDraft(title: "Q3/Q4 plan"))).id!
        let t = ok(.createTask(TaskDraft(title: "T", body: "[[Q3/Q4 plan]]"))).id!
        XCTAssertEqual(try body(t), "[Q3/Q4 plan](gly://item/\(p))")
    }

    func testPageCreatedLaterResolvesATagPathLink() throws {
        let t = ok(.createTask(TaskDraft(title: "T", body: "[[person/alex/Goals]]"))).id!
        XCTAssertEqual(try body(t), "[[person/alex/Goals]]")
        let page = ok(.createPage(PageDraft(title: "Goals", tags: ["person/alex"]))).id!
        XCTAssertEqual(try body(t), "[Goals](gly://item/\(page))")
    }
}

extension LinkDisambiguationTests {
    func testPickACandidate() throws {
        let alex = ok(.createPage(PageDraft(title: "Goals", tags: ["person/alex"]))).id!
        ok(.createPage(PageDraft(title: "Goals", tags: ["person/sam"])))
        let t = ok(.createTask(TaskDraft(title: "T", body: "first [[Goals]] then [[Goals]]")))
        let candidates = try db.read { try LinkResolver.candidates($0, typed: "Goals") }
        let chosen = candidates.first { $0.id == alex }!
        ok(.resolveLink(sourceTable: "items", sourceID: t.id!, typed: "Goals", target: chosen))
        XCTAssertEqual(try body(t.id!), "first [Goals](gly://item/\(alex)) then [[Goals]]", "only the chosen occurrence is pinned")
        ok(.undo)
        XCTAssertEqual(try body(t.id!), "first [[Goals]] then [[Goals]]", "one undo step")
    }

    func testSearchHitsCarryTagsAndModified() throws {
        ok(.createPage(PageDraft(title: "Goals", tags: ["person/alex"])))
        let hit = try db.read { try SearchQueries.search($0, "goals") }.pages.first
        XCTAssertEqual(hit?.tags, ["person/alex"])
        XCTAssertNotNil(hit?.modifiedAt)
    }

    func testUnderTagListsItemsAndSubtags() throws {
        ok(.createPage(PageDraft(title: "Goals", tags: ["person/alex/work"])))
        ok(.createTask(TaskDraft(title: "Call", tags: ["person/alex"])))
        let done = ok(.createTask(TaskDraft(title: "Old", tags: ["person/alex"]))).id!
        ok(.setStatus(id: done, .done))
        ok(.createPage(PageDraft(title: "Other", tags: ["person/sam"])))
        let hits = try db.read { try SearchQueries.underTag($0, try TagName("Person/Alex")) }
        XCTAssertEqual(Set(hits.filter { $0.ref.kind != .tag }.map(\.ref.title)), ["Goals", "Call"], "descendants included, done task and other tags not")
        XCTAssertEqual(hits.last?.ref.title, "person/alex/work", "subtags after the items")
        XCTAssertEqual(hits.first { $0.ref.title == "Goals" }?.tags, ["person/alex/work"])
        let pagesOnly = try db.read { try SearchQueries.underTag($0, try TagName("person/alex"), kinds: [.page]) }
        XCTAssertEqual(pagesOnly.map(\.ref.title), ["Goals"])
    }

    func testNewPageForTypedLink() {
        XCTAssertEqual(LinkResolver.newItem(for: "person/alex/Goals", kind: .page)?.title, "Goals")
        XCTAssertEqual(LinkResolver.newItem(for: "person/alex/Goals", kind: .page)?.tags, ["person/alex"])
        XCTAssertEqual(LinkResolver.newItem(for: "page: Goals", kind: .page)?.title, "Goals")
        XCTAssertEqual(LinkResolver.newItem(for: "Goals", kind: .page)?.tags, [])
        XCTAssertNil(LinkResolver.newItem(for: "task:Goals", kind: .page))
        XCTAssertNil(LinkResolver.newItem(for: "person/alex/", kind: .page), "no title typed yet")
        XCTAssertEqual(LinkResolver.newItem(for: "task: person/alex/Call", kind: .task)?.title, "Call")
        XCTAssertEqual(LinkResolver.newItem(for: "person/alex/Call", kind: .task)?.tags, ["person/alex"])
        XCTAssertNil(LinkResolver.newItem(for: "page:Call", kind: .task))
        XCTAssertNil(LinkResolver.newItem(for: "Call", kind: .tag))
    }

    func testNewTaskResolvesWaitingLink() throws {
        let page = ok(.createPage(PageDraft(title: "P", body: "todo: [[person/alex/Call]]"))).id!
        let task = ok(.createTask(TaskDraft(title: "Call", tags: ["person/alex"]))).id!
        XCTAssertEqual(try body(page), "todo: [Call](gly://item/\(task))")
    }
}
