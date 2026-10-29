import XCTest
@testable import GlyCore

/// specs/quick-capture "Inline syntax", design Q1.
final class CaptureParserTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)
    let tue = LocalDay("2026-10-27")!   // a Tuesday

    func parse(_ text: String, _ kind: CaptureKind = .task) -> CaptureDraft { CaptureParser.parse(text, kind: kind, today: tue, calendar: cal) }

    func testTaskWithTagDueDateAndPriority() {
        let d = parse("Call venue tomorrow #project/atlas !")
        XCTAssertEqual(d.title, "Call venue")
        XCTAssertEqual(d.due, LocalDay("2026-10-28"))
        XCTAssertEqual(d.tags, ["project/atlas"])
        XCTAssertEqual(d.priority, .high)
        XCTAssertEqual(d.preview(today: tue), "Task · Call venue · due Wed 28 Oct · project/atlas · high")
        XCTAssertEqual(d.taskDraft.due, Due(day: "2026-10-28"))
    }

    func testWordsThatOnlyLookLikeDates() {
        let page = parse("Prepare friday retro", .page)
        XCTAssertEqual(page.title, "Prepare friday retro")
        XCTAssertNil(page.due)
        XCTAssertEqual(parse("Prepare friday retro").due, nil, "not at the end: stays in the title")
        XCTAssertEqual(parse("Retro fri #x").due, LocalDay("2026-10-30"), "at the end (before tags): due")
    }

    func testDueForms() {
        XCTAssertEqual(parse("a today").due, tue)
        XCTAssertEqual(parse("a Tuesday").due, LocalDay("2026-11-03"), "today's weekday is a week ahead")
        XCTAssertEqual(parse("a mon").due, LocalDay("2026-11-02"))
        XCTAssertEqual(parse("a 3 Nov").due, LocalDay("2026-11-03"))
        XCTAssertEqual(parse("a 3. November").due, LocalDay("2026-11-03"))
        XCTAssertEqual(parse("a 1 Oct").due, LocalDay("2027-10-01"), "already past: next year")
        XCTAssertEqual(parse("a 2026-12-24").due, LocalDay("2026-12-24"))
        XCTAssertEqual(parse("Room 3 Nov").title, "Room", "the date words are removed")
        XCTAssertEqual(parse("Buy 3 apples").due, nil)
    }

    func testPriorityTagsAndEdges() {
        XCTAssertEqual(parse("x !!").priority, .urgent)
        XCTAssertEqual(parse("x ! !!").priority, .urgent, "last one wins")
        XCTAssertEqual(parse("price # tag").title, "price # tag", "a lone # stays in the title")
        XCTAssertEqual(parse("x #A/b #a/B").tags, ["A/b"], "duplicate tags once")
        let page = parse("Ideas tomorrow ! #p", .page)
        XCTAssertEqual(page.title, "Ideas tomorrow")
        XCTAssertEqual(page.priority, .none)
        XCTAssertEqual(page.tags, ["p"])
        XCTAssertTrue(parse("#only tomorrow").isEmpty, "only syntax: no title, nothing to create")
        XCTAssertTrue(parse("   ").isEmpty)
    }

    // MARK: Bookmarks (bookmarks B6)

    func testBookmarkURLTitleAndTags() {
        let d = parse("https://Wiki.example/runbook #project/atlas", .bookmark)
        XCTAssertEqual(d.url, "https://wiki.example/runbook")
        XCTAssertEqual(d.title, "")
        XCTAssertEqual(d.tags, ["project/atlas"])
        XCTAssertFalse(d.isEmpty, "a URL is enough; the title comes from the page")
        XCTAssertEqual(d.preview(today: tue, fetching: true), "Bookmark · fetching title… · wiki.example · project/atlas")
        XCTAssertEqual(d.preview(today: tue, fetchedTitle: "Runbook"), "Bookmark · Runbook · wiki.example · project/atlas")
        XCTAssertEqual(d.bookmarkDraft(fetchedTitle: "Runbook"), BookmarkDraft(url: "https://wiki.example/runbook", title: "Runbook", tags: ["project/atlas"]))

        let titled = parse("On-call runbook https://wiki.example/runbook tomorrow !", .bookmark)
        XCTAssertEqual(titled.title, "On-call runbook tomorrow", "no due date for bookmarks")
        XCTAssertEqual(titled.bookmarkDraft(fetchedTitle: "Fetched").title, "On-call runbook tomorrow", "a typed title wins")
        XCTAssertNil(titled.due)
        XCTAssertEqual(titled.priority, .none)

        XCTAssertTrue(parse("just words", .bookmark).isEmpty, "no URL, nothing to create")
        XCTAssertEqual(parse("words", .bookmark).preview(today: tue), "Bookmark · (no URL)")
    }

    func testTabCyclesTheKinds() {
        XCTAssertEqual(CaptureKind.task.next, .page)
        XCTAssertEqual(CaptureKind.page.next, .bookmark)
        XCTAssertEqual(CaptureKind.bookmark.next, .task)
    }

    func testPageTitle() {
        XCTAssertEqual(PageTitle.extract(html: "<html><head><TITLE lang=en>\n  Runbook &amp; On-call\n</title>"), "Runbook & On-call")
        XCTAssertEqual(PageTitle.extract(html: "<title>Caf&#233; &#x2014; &quot;menu&quot; &bogus; a & b</title>"), "Café — \"menu\" &bogus; a & b")
        XCTAssertNil(PageTitle.extract(html: "<title>   </title>"))
        XCTAssertNil(PageTitle.extract(html: "<h1>No title</h1>"))
    }
}
