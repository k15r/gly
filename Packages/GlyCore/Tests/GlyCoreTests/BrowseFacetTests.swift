import GRDB
import XCTest
@testable import GlyCore

/// specs/item-browser "Refine by tags", "Grouping and sorting"; specs/tags "Tag tree" counts (item-browser I2, I5).
final class BrowseFacetTests: XCTestCase {
    var db: DatabaseQueue!
    var h: CommandHandler!
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }()
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 10))!
    lazy var today = LocalDay(date: now, calendar: cal)

    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    @discardableResult
    func ok(_ c: Command) -> String { if case .ok(let r) = h.perform(c, writer: "u", now: now) { return r.id ?? "" }; XCTFail("\(c)"); return "" }
    @discardableResult
    func task(_ title: String, tags: [String] = [], due: Int? = nil) -> String {
        ok(.createTask(TaskDraft(title: title, due: due.map { Due(day: today.adding(days: $0, calendar: cal).description) }, tags: tags)))
    }
    func items(_ q: String, sort: ItemSort = .title) throws -> [BrowseItem] {
        try db.read { try BrowseQueries.items($0, ItemQuery.parse(q), sort: sort, now: now, calendar: cal) }
    }

    func testWhoIsInvolved() throws {
        for n in 1...4 { task("A\(n)", tags: ["project/atlas", n <= 2 ? "person/sam" : "person/x"]) }
        for n in 1...4 { task("Alex \(n)", tags: ["project/atlas", "person/alex"]) }
        task("Elsewhere", tags: ["person/alex"])
        let q = ItemQuery.parse("is:task #project/atlas")
        let refine = BrowseFacets.refine(try items(q.description), query: q)
        XCTAssertEqual(refine.map(\.tag), ["person/alex", "person/sam", "person/x"])
        XCTAssertEqual(refine.map(\.count), [4, 2, 2])
        XCTAssertFalse(refine.contains { $0.tag.hasPrefix("project") }, "the filtered tag and those above it are left out")
        let narrowed = q.adding(.tag("person/alex"))
        XCTAssertEqual(try items(narrowed.description).count, 4)
    }

    func testTagCountsFollowTheView() throws {
        // "Tag hierarchy with counts", "Counts follow the view", "Empty tag".
        task("T1", tags: ["person/alex"]); task("T2", tags: ["person/alex"]); task("T3", tags: ["person/sam"])
        ok(.createBookmark(BookmarkDraft(url: "https://example.com", title: "B", tags: ["person/alex"])))
        ok(.createTag(name: "person/alex/goals"))
        let tasksView = ItemQuery.parse("is:task status:open status:snoozed #person/sam")
        let counts = BrowseFacets.tagCounts(try items(tasksView.droppingTags().description))
        XCTAssertEqual(counts["person"], 3)
        XCTAssertEqual(counts["person/alex"], 2)
        XCTAssertEqual(counts["person/sam"], 1)
        XCTAssertNil(counts["person/alex/goals"], "an empty tag counts 0 (absent)")
        let bookmarkCounts = BrowseFacets.tagCounts(try items("is:bookmark"))
        XCTAssertEqual(bookmarkCounts["person/alex"], 1)
        XCTAssertEqual(BrowseFacets.untaggedCount(try items("")), 0)
    }

    func testGroupByDueDate() throws {
        task("Overdue", due: -1); task("Today", due: 0); task("Week", due: 4); task("Later", due: 20); task("None")
        ok(.createPage(PageDraft(title: "Page")))
        let groups = BrowseGroups.group(try items("", sort: .due), by: .due, query: ItemQuery(), sort: .due, today: today, calendar: cal)
        XCTAssertEqual(groups.map(\.title), ["Overdue", "Today", "This week", "Later", "No due date"])
        XCTAssertEqual(groups.last?.items.map(\.title).sorted(), ["None", "Page"])
    }

    func testGroupByKindAsOnTagPages() throws {
        let done = task("Done", tags: ["p"]); ok(.setStatus(id: done, .done))
        task("Open", tags: ["p"])
        ok(.createPage(PageDraft(title: "Page", tags: ["p"])))
        ok(.createBookmark(BookmarkDraft(url: "https://example.com", title: "Bm", tags: ["p"])))
        let q = ItemQuery.parse("#p")
        let groups = BrowseGroups.group(try items(q.description, sort: .taskOrder), by: .kind, query: q, sort: .taskOrder, today: today)
        XCTAssertEqual(groups.map(\.title), ["Open tasks", "Pages", "Bookmarks", "Finished tasks"])
        XCTAssertEqual(groups.last?.collapsed, true)
    }

    func testGroupByStatusAndTag() throws {
        let s = task("Snoozed", tags: ["project/atlas/logs"]); ok(.setStatus(id: s, .snoozed, snoozedUntil: "2026-11-05"))
        task("Open", tags: ["project/atlas", "project/beta"])
        task("Loose")
        let byStatus = BrowseGroups.group(try items("is:task"), by: .status, query: ItemQuery(), sort: .title, today: today)
        XCTAssertEqual(byStatus.map(\.title), ["Open", "Snoozed"])
        let q = ItemQuery.parse("#project")
        let byTag = BrowseGroups.group(try items(q.description), by: .tag, query: q, sort: .title, today: today)
        XCTAssertEqual(byTag.map(\.title), ["project/atlas", "project/beta"])
        XCTAssertEqual(byTag.first?.items.map(\.title), ["Open", "Snoozed"], "the level below the filtered tag")
        let top = BrowseGroups.group(try items("is:task"), by: .tag, query: ItemQuery(), sort: .title, today: today)
        XCTAssertEqual(top.map(\.title), ["project", "Untagged"])
    }
}
