import GRDB
import XCTest
@testable import GlyCore

/// specs/bookmarks through commands and queries (bookmarks B1, B2).
final class BookmarkTests: XCTestCase {
    let me = "user@mac"
    let dashboard = "https://grafana.example/d/latency"
    var db: DatabaseQueue!
    var h: CommandHandler!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    @discardableResult
    func ok(_ c: Command, file: StaticString = #filePath, line: UInt = #line) -> CommandOK {
        switch h.perform(c, writer: me) {
        case .ok(let r): return r
        case .failure(let f): XCTFail("unexpected failure \(f)", file: file, line: line); return CommandOK()
        }
    }
    func failure(_ c: Command) -> CommandFailure? { if case .failure(let f) = h.perform(c, writer: me) { return f }; return nil }
    func undoLabel() throws -> String? { try db.read { try $0.undoLabel(writer: me) } }
    func bookmark(_ id: String) throws -> BookmarkItem? { try db.read { try BookmarkQueries.bookmark($0, id: id) } }
    func list(tag: String? = nil, text: String? = nil) throws -> [String] {
        try db.read { db in try BookmarkQueries.list(db, tag: try tag.map(TagName.init), text: text).map(\.title) }
    }
    func create(_ title: String, _ url: String, description: String = "", tags: [String] = []) -> String {
        ok(.createBookmark(BookmarkDraft(url: url, title: title, description: description, tags: tags))).id!
    }

    func testCreateABookmark() throws {
        // "Create a bookmark": title, URL and tag stored; ⌘Z removes it again.
        let id = create("Latency dashboard", dashboard, tags: ["project/atlas"])
        let b = try XCTUnwrap(bookmark(id))
        XCTAssertEqual(b.title, "Latency dashboard")
        XCTAssertEqual(b.url, dashboard)
        XCTAssertEqual(b.tags, ["project/atlas"])
        XCTAssertEqual(b.host, "grafana.example")
        XCTAssertEqual(try undoLabel(), "Add bookmark “Latency dashboard”")
        ok(.undo)
        XCTAssertNil(try bookmark(id))
        XCTAssertEqual(try list(), [])
    }

    func testSameURLAgain() throws {
        let id = create("Latency dashboard", dashboard)
        let again = ok(.createBookmark(BookmarkDraft(url: "HTTPS://Grafana.Example/d/latency", title: "Other")))
        XCTAssertEqual(again.id, id, "the existing bookmark")
        XCTAssertFalse(again.changed)
        XCTAssertEqual(try list(), ["Latency dashboard"])
        // Changing another bookmark to the same URL is refused too.
        let other = create("Errors", "https://grafana.example/d/errors")
        XCTAssertEqual(failure(.updateBookmark(id: other, BookmarkPatch(url: dashboard)))?.code, .conflict)
    }

    func testURLNormalization() {
        XCTAssertEqual(BookmarkURL.normalize(" HTTPS://Example.COM/ "), "https://example.com")
        XCTAssertEqual(BookmarkURL.normalize("https://example.com/A/"), "https://example.com/A/", "paths stay exact")
        XCTAssertEqual(BookmarkURL.normalize("https://example.com/?q=1"), "https://example.com/?q=1")
        XCTAssertEqual(BookmarkURL.normalize("mailto:team@example.com"), "mailto:team@example.com")
        XCTAssertNil(BookmarkURL.normalize("ftp://example.com"))
        XCTAssertNil(BookmarkURL.normalize("not a link"))
        XCTAssertEqual(failure(.createBookmark(BookmarkDraft(url: "file:///etc/hosts")))?.code, .validation)
    }

    func testTitleFallsBackToTheHost() throws {
        let id = create("  ", "https://wiki.example/runbook")
        XCTAssertEqual(try bookmark(id)?.title, "wiki.example")
    }

    func testUpdateAndLabels() throws {
        let id = create("Latency", dashboard)
        ok(.updateBookmark(id: id, BookmarkPatch(title: "Latency dashboard", description: "p99 by service", tags: ["ops"])))
        XCTAssertEqual(try undoLabel(), "Edit bookmark “Latency dashboard”")
        let b = try XCTUnwrap(bookmark(id))
        XCTAssertEqual(b.description, "p99 by service")
        XCTAssertEqual(b.tags, ["ops"])
        XCTAssertFalse(ok(.updateBookmark(id: id, BookmarkPatch(title: "Latency dashboard"))).changed)
        ok(.undo)
        XCTAssertEqual(try bookmark(id)?.title, "Latency", "one step for title, description and tags")
        XCTAssertEqual(try bookmark(id)?.tags, [])
    }

    func testFilterByTag() throws {
        create("Latency dashboard", dashboard, tags: ["project/atlas/ops"])
        create("Atlas wiki", "https://wiki.example/atlas", tags: ["project/atlas"])
        create("Recipes", "https://food.example", tags: ["home"])
        XCTAssertEqual(try list(tag: "project/atlas"), ["Atlas wiki", "Latency dashboard"], "the tag or below it")
        XCTAssertEqual(try list(tag: "home"), ["Recipes"])
    }

    func testListByText() throws {
        create("Latency dashboard", dashboard, description: "p99 by service", tags: ["ops"])
        create("Recipes", "https://food.example")
        XCTAssertEqual(try list(text: "P99"), ["Latency dashboard"], "description")
        XCTAssertEqual(try list(text: "grafana"), ["Latency dashboard"], "URL")
        XCTAssertEqual(try list(text: "ops"), ["Latency dashboard"], "tags")
        XCTAssertEqual(try list(text: "late dash"), ["Latency dashboard"], "every word")
        XCTAssertEqual(try list(text: "food"), ["Recipes"])
    }

    func testSearchByDescription() throws {
        let id = create("Latency dashboard", dashboard, description: "p99 by service", tags: ["project/atlas"])
        create("Atlas", "https://wiki.example/atlas")
        let byText = try db.read { try SearchQueries.search($0, "p99") }
        XCTAssertEqual(byText.bookmarks.map(\.id), [id])
        XCTAssertEqual(byText.bookmarks.first?.url, dashboard)
        XCTAssertEqual(byText.bookmarks.first?.tags, ["project/atlas"])
        XCTAssertEqual(try db.read { try SearchQueries.search($0, "grafana") }.bookmarks.map(\.id), [id], "by URL")
        XCTAssertEqual(try db.read { try SearchQueries.search($0, "project/atl") }.bookmarks.map(\.id), [id], "by tag")
        XCTAssertTrue(byText.pages.isEmpty && byText.tasks.isEmpty, "bookmarks aren't pages or tasks")
    }

    func testLookupByURLs() throws {
        let id = create("Latency dashboard", dashboard)
        let found = try db.read { try BookmarkQueries.bookmarks($0, urls: ["https://GRAFANA.example/d/latency", "https://other.example"]) }
        XCTAssertEqual(found.mapValues(\.id), ["https://GRAFANA.example/d/latency": id])
    }

    func testDeleteAndRestoreFromTheTrash() throws {
        let id = create("Latency dashboard", dashboard, tags: ["ops"])
        ok(.deleteBookmark(id: id))
        XCTAssertEqual(try undoLabel(), "Delete bookmark “Latency dashboard”")
        XCTAssertEqual(try list(), [])
        XCTAssertTrue(try db.read { try SearchQueries.search($0, "latency") }.bookmarks.isEmpty)
        let entry = try XCTUnwrap(try db.read { try TrashQueries.list($0) }.first)
        XCTAssertEqual(entry.kind, .bookmark)
        XCTAssertEqual(entry.tags, ["ops"])
        ok(.restore(id: id))
        XCTAssertEqual(try bookmark(id)?.tags, ["ops"])
        XCTAssertEqual(try undoLabel(), "Restore bookmark “Latency dashboard”")
    }

    func testRestoreWhileTheURLIsBookmarkedAgain() throws {
        let id = create("Latency dashboard", dashboard)
        ok(.deleteBookmark(id: id))
        create("Latency (new)", dashboard)
        XCTAssertEqual(failure(.restore(id: id))?.code, .conflict)
    }

    func testBookmarkCommandsRejectOtherItems() {
        let page = ok(.createPage(PageDraft(title: "P"))).id!
        XCTAssertEqual(failure(.updateBookmark(id: page, BookmarkPatch(title: "x")))?.code, .notFound)
        XCTAssertEqual(failure(.deleteBookmark(id: page))?.code, .notFound)
    }
}
