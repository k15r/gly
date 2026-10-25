import GRDB
import XCTest
@testable import StoreSpike

final class SearchTests: XCTestCase {
    func timed<T>(_ label: String, _ body: () throws -> T) rethrows -> (T, Double) {
        _ = try body()                                   // warm-up
        var best = Double.infinity
        var r: T!
        for _ in 0..<5 {
            let t0 = Date(); r = try body(); best = min(best, Date().timeIntervalSince(t0) * 1000)
        }
        print(String(format: "search %-28@ %6.2f ms", label as NSString, best))
        return (r, best)
    }

    func testPrefixFindsCompoundWord() throws {
        try Fixture.store.db.read { db in
            // Synthetic texts reuse a small vocabulary, so "budg*" matches thousands of items:
            // check presence in the full result, and time the UI-sized (limit 50) query.
            let (_, ms) = try timed("budg* (limit 50)") { try db.search("budg*") }
            let (all, msAll) = try timed("budg* (all)") { try db.search("budg*", limit: 100_000) }
            XCTAssertTrue(all.contains { $0.title == "Budgetfreigabe Lasttests Q1" }, "prefix search must find the compound word")
            XCTAssertLessThan(ms, 50)
            print(String(format: "search budg* total hits %d (%.1f ms for all)", all.count, msAll))
        }
    }

    func testUmlautsMatchWithoutDiacritics() throws {
        try Fixture.store.db.read { db in
            let (plain, ms) = try timed("Prufung") { try db.search("Prufung") }
            let (umlaut, _) = try timed("Prüfung") { try db.search("Prüfung") }
            XCTAssertFalse(plain.isEmpty)
            XCTAssertEqual(Set(plain.map(\.id)), Set(umlaut.map(\.id)))
            XCTAssertLessThan(ms, 50)
        }
    }

    func testTagPagesAreSearchable() throws {
        try Fixture.store.db.read { db in
            let (hits, ms) = try timed("Seite") { try db.search("Seite") }
            XCTAssertTrue(hits.contains { $0.kind == "tag" })
            XCTAssertLessThan(ms, 50)
        }
    }

    func testIndexFollowsUpdatesAndHidesTombstones() throws {
        let store = try Store()
        try store.migrate()
        let user = Writer("user@mac")
        try store.db.write { db in
            let id = try db.insert("items", ["kind": "info", "title": "Kickoff Notizen", "body": "erste Version"], by: user)
            XCTAssertEqual(try db.search("Kickoff").map(\.id), [id])
            try db.update("items", id: id, ["title": "Abschluss Notizen"], by: user)
            XCTAssertTrue(try db.search("Kickoff").isEmpty, "old title must leave the index")
            XCTAssertEqual(try db.search("Abschluss").map(\.id), [id])
            try db.softDelete("items", id: id, by: user)
            XCTAssertTrue(try db.search("Abschluss").isEmpty, "tombstones must not be found")
            try db.undoLast(by: user)
            XCTAssertEqual(try db.search("Abschluss").map(\.id), [id], "undo brings it back")
        }
    }
}
