import GRDB
import XCTest
@testable import GlyCore

/// specs/links "Duplicate titles are distinguishable".
final class DisambiguationTests: XCTestCase {
    var db: DatabaseQueue!
    var h: CommandHandler!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }
    @discardableResult func make(_ c: Command, at: Date = Date()) -> String {
        guard case .ok(let r) = h.perform(c, writer: "u", now: at) else { XCTFail(); return "" }
        return r.id ?? ""
    }
    func display(_ id: String) throws -> String? { try db.read { try DisplayNames.display($0, ids: [id]) }[id]?.display }

    func testUniqueTitleHasNoQualifier() throws {
        let id = make(.createPage(PageDraft(title: "Atlas architecture", tags: ["project/atlas"])))
        XCTAssertEqual(try display(id), "Atlas architecture")
    }

    func testQualifierAppearsWithADuplicateAndFollowsTags() throws {
        let alex = make(.createPage(PageDraft(title: "Goals", tags: ["person/alex", "goals"])))
        XCTAssertEqual(try display(alex), "Goals")
        let sam = make(.createPage(PageDraft(title: "goals", tags: ["person/sam", "goals"])))
        XCTAssertEqual(try display(alex), "Goals · person/alex", "shared tag `goals` is not distinguishing")
        XCTAssertEqual(try display(sam), "goals · person/sam")
        make(.updatePage(id: sam, PagePatch(tags: ["person/kim"])))
        XCTAssertEqual(try display(sam), "goals · person/kim")
        make(.deletePage(id: sam))
        XCTAssertEqual(try display(alex), "Goals", "qualifier disappears with the duplicate")
    }

    func testDeepestUniqueTagWins() {
        let q = Disambiguation.qualifiers([
            .init(id: "a", title: "Notes", tags: ["project", "project/atlas/logs", "team"], createdAt: Date()),
            .init(id: "b", title: "Notes", tags: ["project", "team"], createdAt: Date()),
        ])
        XCTAssertEqual(q["a"], "project/atlas/logs")
        XCTAssertTrue(q["b"]!.hasPrefix("created "), "no unique tag → creation date")
    }

    func testSameTagsFallBackToCreationDate() throws {
        let d1 = Date(timeIntervalSince1970: 1_790_000_000), d2 = d1.addingTimeInterval(5 * 86400)
        let a = make(.createPage(PageDraft(title: "Notes", tags: ["x"])), at: d1)
        _ = make(.createPage(PageDraft(title: "Notes", tags: ["x"])), at: d2)
        XCTAssertTrue(try display(a)!.hasPrefix("Notes · created "))
    }

    func testPagesAndTasksAreScopedSeparately() throws {
        let page = make(.createPage(PageDraft(title: "Offsite", tags: ["project/a"])))
        make(.createTask(TaskDraft(title: "Offsite", tags: ["project/b"])))
        XCTAssertEqual(try display(page), "Offsite", "a task with the same title doesn't qualify a page")
    }
}
