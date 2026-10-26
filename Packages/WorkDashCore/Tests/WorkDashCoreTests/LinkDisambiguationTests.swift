import GRDB
import XCTest
@testable import WorkDashCore

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
        XCTAssertEqual(try body(t.id!), "see [Goals](workdash://item/\(alex))")
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
        XCTAssertTrue(try body(page.id!).hasSuffix("[Offsite](workdash://item/\(task))"))
        ok(.createPage(PageDraft(title: "Q", tags: ["project/atlas"])))
        let q = ok(.createPage(PageDraft(title: "R", body: "[[tag:project/atlas]]")))
        XCTAssertTrue(try body(q.id!).contains("workdash://tag/"))
    }

    func testResolvedOnceSurvivesTagChanges() throws {
        let alex = ok(.createPage(PageDraft(title: "Goals", tags: ["person/alex"]))).id!
        ok(.createPage(PageDraft(title: "Goals", tags: ["person/sam"])))
        let t = ok(.createTask(TaskDraft(title: "T", body: "[[person/alex/Goals]]"))).id!
        ok(.updatePage(id: alex, PagePatch(tags: ["person/kim"])))
        XCTAssertEqual(try body(t), "[Goals](workdash://item/\(alex))")
    }

    func testTitleContainingSlashStillMatchesExactly() throws {
        let p = ok(.createPage(PageDraft(title: "Q3/Q4 plan"))).id!
        let t = ok(.createTask(TaskDraft(title: "T", body: "[[Q3/Q4 plan]]"))).id!
        XCTAssertEqual(try body(t), "[Q3/Q4 plan](workdash://item/\(p))")
    }

    func testPageCreatedLaterResolvesATagPathLink() throws {
        let t = ok(.createTask(TaskDraft(title: "T", body: "[[person/alex/Goals]]"))).id!
        XCTAssertEqual(try body(t), "[[person/alex/Goals]]")
        let page = ok(.createPage(PageDraft(title: "Goals", tags: ["person/alex"]))).id!
        XCTAssertEqual(try body(t), "[Goals](workdash://item/\(page))")
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
        XCTAssertEqual(try body(t.id!), "first [Goals](workdash://item/\(alex)) then [[Goals]]", "only the chosen occurrence is pinned")
        ok(.undo)
        XCTAssertEqual(try body(t.id!), "first [[Goals]] then [[Goals]]", "one undo step")
    }

    func testSearchHitsCarryTagsAndModified() throws {
        ok(.createPage(PageDraft(title: "Goals", tags: ["person/alex"])))
        let hit = try db.read { try SearchQueries.search($0, "goals") }.pages.first
        XCTAssertEqual(hit?.tags, ["person/alex"])
        XCTAssertNotNil(hit?.modifiedAt)
    }

    func testNewPageForTypedLink() {
        XCTAssertEqual(LinkResolver.newPage(for: "person/alex/Goals")?.title, "Goals")
        XCTAssertEqual(LinkResolver.newPage(for: "person/alex/Goals")?.tags, ["person/alex"])
        XCTAssertEqual(LinkResolver.newPage(for: "page: Goals")?.title, "Goals")
        XCTAssertEqual(LinkResolver.newPage(for: "Goals")?.tags, [])
        XCTAssertNil(LinkResolver.newPage(for: "task:Goals"))
        XCTAssertEqual(LinkResolver.newPage(for: "a/")?.title, "a/", "no title after the slash: taken as typed")
    }
}
