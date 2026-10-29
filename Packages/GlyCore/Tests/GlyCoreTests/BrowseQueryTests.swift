import GRDB
import XCTest
@testable import GlyCore

/// specs/item-browser "Filter bar", specs/tags "Filter items by tag including descendants", task-list order (item-browser I1).
final class BrowseQueryTests: XCTestCase {
    let me = "user@mac", agent = "agent:claude-code@mac"
    var db: DatabaseQueue!
    var h: CommandHandler!
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }()
    lazy var now = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 10))!   // a Thursday
    lazy var today = LocalDay(date: now, calendar: cal)

    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    @discardableResult
    func ok(_ c: Command, writer: String? = nil, at date: Date? = nil, file: StaticString = #filePath, line: UInt = #line) -> String {
        switch h.perform(c, writer: writer ?? me, now: date ?? now) {
        case .ok(let r): return r.id ?? ""
        case .failure(let f): XCTFail("\(f)", file: file, line: line); return ""
        }
    }
    func day(_ n: Int) -> String { today.adding(days: n, calendar: cal).description }
    @discardableResult
    func task(_ title: String, due: Int? = nil, tags: [String] = [], priority: Priority = .none, effort: Effort? = nil, body: String = "") -> String {
        ok(.createTask(TaskDraft(title: title, body: body, priority: priority, due: due.map { Due(day: day($0)) }, tags: tags, effort: effort)))
    }
    func titles(_ q: String, sort: ItemSort = .title) throws -> [String] {
        try db.read { try BrowseQueries.items($0, ItemQuery.parse(q), sort: sort, now: now, calendar: cal).map(\.title) }
    }

    func testTypedTokens() throws {
        // "is:task #project/atlas due:week review": tasks under the tag, due within 7 days, with "review" in title or text.
        task("Review deck", due: 2, tags: ["project/atlas"])
        task("Draft plan", due: 3, tags: ["project/atlas/logs"], body: "needs a review first")
        task("Review later", due: 20, tags: ["project/atlas"])
        task("Review other", due: 1, tags: ["project/beta"])
        task("Unrelated", due: 1, tags: ["project/atlas"])
        ok(.createPage(PageDraft(title: "Review notes", tags: ["project/atlas"])))
        XCTAssertEqual(try titles("is:task #project/atlas due:week review"), ["Draft plan", "Review deck"])
    }

    func testKindsAndMeetingsNeedNotes() throws {
        task("T")
        ok(.createPage(PageDraft(title: "P")))
        ok(.createBookmark(BookmarkDraft(url: "https://example.com", title: "B")))
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, body) VALUES
                ('M1', ?, ?, 'u', 'event_note', 'Weekly', 'notes'), ('M2', ?, ?, 'u', 'event_note', 'Blocking only', ''),
                ('L1', ?, ?, 'u', 'local_event', 'Local', '')
                """, arguments: StatementArguments(Array(repeating: now, count: 6)))
        }
        XCTAssertEqual(try titles(""), ["B", "P", "T", "Weekly"])
        XCTAssertEqual(try titles("is:page is:bookmark"), ["B", "P"])
        XCTAssertEqual(try titles("is:meeting"), ["Weekly"])
    }

    func testExcludeATagAndUntagged() throws {
        ok(.createBookmark(BookmarkDraft(url: "https://a.example", title: "Ops board", tags: ["ops/infra"])))
        ok(.createBookmark(BookmarkDraft(url: "https://b.example", title: "Wiki", tags: ["team"])))
        ok(.createBookmark(BookmarkDraft(url: "https://c.example", title: "Loose")))
        XCTAssertEqual(try titles("is:bookmark -#ops"), ["Loose", "Wiki"])
        XCTAssertEqual(try titles("is:bookmark untagged"), ["Loose"])
    }

    func testFilterByPrefixWithoutPartialSegments() throws {
        task("A", tags: ["project/atlas"]); task("B", tags: ["project/atlas/logs"]); task("C", tags: ["person/alex"])
        XCTAssertEqual(try titles("#project"), ["A", "B"])
        XCTAssertEqual(try titles("#person/al"), [], "al is not a full segment")
        XCTAssertEqual(try titles("#project #project/atlas/logs"), ["B"], "several tags must all match")
    }

    func testAgentChanges() throws {
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        ok(.createPage(PageDraft(title: "Agent today")), writer: agent)
        ok(.createPage(PageDraft(title: "Agent yesterday")), writer: agent, at: yesterday)
        ok(.createPage(PageDraft(title: "Mine today")))
        XCTAssertEqual(try titles("by:agent changed:today"), ["Agent today"])
        XCTAssertEqual(try titles("by:agent changed:7d"), ["Agent today", "Agent yesterday"])
        XCTAssertEqual(try titles("by:me"), ["Mine today"])
    }

    func testTaskFields() throws {
        let done = task("Done one", due: -1)
        ok(.setStatus(id: done, .done))
        task("Overdue", due: -2, priority: .high, effort: .l)
        task("Today", due: 0, effort: .s)
        task("No due", priority: .urgent)
        ok(.createPage(PageDraft(title: "Page")))
        XCTAssertEqual(try titles("due:overdue"), ["Overdue"], "finished tasks aren't overdue")
        XCTAssertEqual(try titles("due:today"), ["Today"])
        XCTAssertEqual(try titles("due:none"), ["No due"], "pages have no due date and don't match")
        XCTAssertEqual(try titles("prio:high prio:urgent"), ["No due", "Overdue"])
        XCTAssertEqual(try titles("effort:L"), ["Overdue"])
        XCTAssertEqual(try titles("status:done"), ["Done one", "Page"], "status narrows tasks only")
        XCTAssertEqual(try titles("is:task status:done"), ["Done one"])
    }

    func testHost() throws {
        ok(.createBookmark(BookmarkDraft(url: "https://docs.example.com/a", title: "Docs")))
        ok(.createBookmark(BookmarkDraft(url: "https://example.com", title: "Home")))
        ok(.createBookmark(BookmarkDraft(url: "https://notexample.com", title: "Other")))
        XCTAssertEqual(try titles("host:example.com"), ["Docs", "Home"])
    }

    func testText() throws {
        task("Call venue", body: "about the offsite")
        ok(.createPage(PageDraft(title: "Offsite ideas")))
        ok(.createBookmark(BookmarkDraft(url: "https://example.com/latency", title: "Dashboard", description: "p99 by service")))
        XCTAssertEqual(try titles("offsite"), ["Call venue", "Offsite ideas"])
        XCTAssertEqual(try titles("p99"), ["Dashboard"])
        XCTAssertEqual(try titles("offsite", sort: .relevance).first, "Offsite ideas", "title matches rank first")
        XCTAssertEqual(try titles("\"\""), [], "nothing searchable")
    }

    func testTaskListOrderAndDoneOrder() throws {
        task("Urgent no due", priority: .urgent)
        task("Normal tomorrow", due: 1, priority: .normal)
        task("Normal today", due: 0, priority: .normal)
        XCTAssertEqual(try titles("is:task status:open status:snoozed", sort: .taskOrder), ["Urgent no due", "Normal today", "Normal tomorrow"])
        let first = task("Finished first"), second = task("Finished second")
        ok(.setStatus(id: first, .done), at: now.addingTimeInterval(60))
        ok(.setStatus(id: second, .done), at: now.addingTimeInterval(120))
        XCTAssertEqual(try titles("is:task status:done", sort: .taskOrder), ["Finished second", "Finished first"], "most recently completed first")
    }

    func testCount() throws {
        task("A", tags: ["x"]); task("B"); ok(.createPage(PageDraft(title: "P", tags: ["x"])))
        XCTAssertEqual(try db.read { try BrowseQueries.count($0, ItemQuery.parse("#x"), now: now, calendar: cal) }, 2)
        XCTAssertEqual(try db.read { try BrowseQueries.count($0, ItemQuery.parse("is:task"), now: now, calendar: cal) }, 2)
        XCTAssertEqual(try db.read { try BrowseQueries.count($0, ItemQuery.parse("nothing"), now: now, calendar: cal) }, 0)
    }

    func testRowsCarryTasksURLsAndTags() throws {
        let t = task("T", tags: ["a"])
        ok(.createBookmark(BookmarkDraft(url: "https://example.com", title: "B", description: "line one\nline two")))
        let items = try db.read { try BrowseQueries.items($0, ItemQuery(), sort: .title, now: now, calendar: cal) }
        XCTAssertEqual(items.first { $0.kind == .bookmark }?.url, "https://example.com")
        XCTAssertEqual(items.first { $0.kind == .bookmark }?.excerpt, "line one line two")
        XCTAssertEqual(items.first { $0.id == t }?.task?.title, "T")
        XCTAssertEqual(items.first { $0.id == t }?.tags, ["a"])
    }

    func testFiveThousandItemsAreFast() throws {
        try db.write { db in
            for n in 0..<5000 {
                let id = UUID().uuidString
                try db.execute(sql: """
                    INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, body, status, priority, due_day)
                    VALUES (?, ?, ?, 'u', ?, ?, 'some text about things', ?, 'none', ?)
                    """, arguments: [id, now, now, n % 3 == 0 ? "info" : "task", "Item \(n)", n % 3 == 0 ? nil : "open", n % 3 == 0 ? nil : day(n % 30)])
                try db.execute(sql: "INSERT INTO tags (id, created_at, modified_at, modified_by, name, name_key) VALUES (?, ?, ?, 'u', ?, ?) ON CONFLICT DO NOTHING",
                               arguments: ["T\(n % 50)", now, now, "project/p\(n % 50)", "project/p\(n % 50)"])
                try db.execute(sql: "INSERT INTO item_tags (id, created_at, modified_at, modified_by, item_id, tag_id) VALUES (?, ?, ?, 'u', ?, ?)",
                               arguments: [UUID().uuidString, now, now, id, "T\(n % 50)"])
            }
            try DerivedIndex.rebuild(db)
        }
        // The spec's 100 ms holds for the app (release: ~40 ms for all 5,000); unoptimized test builds get more room.
        #if DEBUG
        let budget = 0.25
        #else
        let budget = 0.1
        #endif
        for q in ["is:task status:open #project due:week", "is:page", "things #project/p7", ""] {
            let start = Date()
            _ = try db.read { try BrowseQueries.items($0, ItemQuery.parse(q), sort: .taskOrder, now: now, calendar: cal) }
            XCTAssertLessThan(Date().timeIntervalSince(start), budget, q)
        }
    }
}
