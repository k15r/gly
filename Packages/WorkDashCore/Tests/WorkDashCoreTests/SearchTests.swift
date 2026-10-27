import GRDB
import XCTest
@testable import WorkDashCore

/// specs/search.
final class SearchTests: XCTestCase {
    var db: DatabaseQueue!
    var h: CommandHandler!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    @discardableResult
    func make(_ c: Command) -> String {
        guard case .ok(let r) = h.perform(c, writer: "u") else { XCTFail("\(c)"); return "" }
        return r.id ?? ""
    }
    func search(_ q: String) throws -> SearchResults { try db.read { try SearchQueries.search($0, q) } }

    func testPrefixMatch() throws {
        make(.createPage(PageDraft(title: "Budget approval")))
        XCTAssertEqual(try search("budg").pages.map(\.ref.title), ["Budget approval"])
    }

    func testDiacritics() throws {
        make(.createPage(PageDraft(title: "Q3", body: "Ein Überblick über alles")))
        let hit = try search("uberblick").pages.first
        XCTAssertEqual(hit?.ref.title, "Q3")
        XCTAssertTrue(hit?.excerpt.contains("Überblick") ?? false, "excerpt shows the original text")
    }

    func testGroupedResults() throws {
        make(.createPage(PageDraft(title: "Atlas architecture")))
        make(.createPage(PageDraft(title: "Notes", body: "atlas load test")))
        make(.createTask(TaskDraft(title: "Review atlas plan")))
        make(.updateTagPage(name: "project/atlas", body: "The project"))
        let r = try search("atlas")
        XCTAssertEqual(Set(r.pages.map(\.ref.title)), ["Atlas architecture", "Notes"])
        XCTAssertEqual(r.pages.first?.ref.title, "Atlas architecture", "title matches rank first")
        XCTAssertEqual(r.tasks.map(\.ref.title), ["Review atlas plan"])
        XCTAssertEqual(r.tags.map(\.ref.title), ["project/atlas"])
    }

    func testMultipleWordsAndQuotes() throws {
        make(.createPage(PageDraft(title: "Atlas architecture")))
        make(.createPage(PageDraft(title: "Atlas budget")))
        XCTAssertEqual(try search("atlas arch").pages.map(\.ref.title), ["Atlas architecture"])
        XCTAssertNoThrow(try search("\"broken query"))
        XCTAssertTrue(try search("   ").isEmpty)
    }

    func testDeletedItemsAreNotFound() throws {
        let id = make(.createPage(PageDraft(title: "Secret plan")))
        make(.deletePage(id: id))
        XCTAssertTrue(try search("secret").isEmpty)
        make(.undo)
        XCTAssertEqual(try search("secret").pages.count, 1, "restored items are found again")
    }

    func testLinkMarkupIsNotSearched() throws {
        let target = make(.createPage(PageDraft(title: "Target")))
        make(.createPage(PageDraft(title: "Source", body: "see [[Target]]")))
        XCTAssertEqual(try search("gly").pages.count, 0)
        XCTAssertEqual(try search(String(target.prefix(8))).pages.count, 0)
    }

    func testTenThousandItemsUnder100ms() throws {
        try db.write { db in
            let words = ["atlas", "budget", "review", "plan", "notes", "load", "test", "release", "team", "sync", "Überblick", "freigabe"]
            for n in 0..<10_000 {
                let body = (0..<30).map { words[($0 * 7 + n) % words.count] }.joined(separator: " ")
                try db.execute(sql: """
                    INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, body, status, priority)
                    VALUES (?, '2026-10-26', '2026-10-26', 'u', ?, ?, ?, ?, 'none')
                    """, arguments: [UUID().uuidString, n % 3 == 0 ? "info" : "task", "Item \(n) \(words[n % words.count])", body, n % 3 == 0 ? nil : "open"])
            }
            try DerivedIndex.rebuild(db)
        }
        var times: [Double] = []
        for q in ["atl", "budget rev", "uberbl", "release team", "sync", "notes pl"] {
            let start = Date()
            let r = try search(q)
            times.append(Date().timeIntervalSince(start) * 1000)
            XCTAssertFalse(r.isEmpty, q)
        }
        let median = times.sorted()[times.count / 2]
        print("search median \(String(format: "%.1f", median)) ms, max \(String(format: "%.1f", times.max()!)) ms")
        XCTAssertLessThan(median, 100)
    }
}
