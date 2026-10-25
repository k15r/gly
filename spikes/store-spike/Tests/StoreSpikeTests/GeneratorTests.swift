import GRDB
import XCTest
@testable import StoreSpike

/// Shared generated database for the generator, filter and FTS tests (built once per test run).
enum Fixture {
    static let store: Store = {
        let s = try! Store()
        try! s.migrate()
        let start = Date()
        _ = try! s.db.write { try $0.generate() }
        print("fixture generated in \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
        return s
    }()
}

final class GeneratorTests: XCTestCase {
    func testGeneratedDatabaseHasExpectedRowCounts() throws {
        try Fixture.store.db.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items"), 10_000)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags"), 501)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM property_values"), 50_000)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM property_keys"), 20)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM links"), 5_000)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recurrences"), 50)
            let itemTags = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item_tags")!
            XCTAssertTrue((15_000...25_000).contains(itemTags), "item_tags \(itemTags)")
            // All kinds and some tombstones present
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT kind) FROM items"), 4)
            let tombstones = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items WHERE deleted_at IS NOT NULL")!
            XCTAssertTrue((200...400).contains(tombstones), "tombstones \(tombstones)")
            // Every property value sets exactly one typed column
            XCTAssertEqual(try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM property_values
                WHERE (text_value IS NOT NULL) + (number_value IS NOT NULL) + (date_value IS NOT NULL)
                    + (bool_value IS NOT NULL) + (ref_value IS NOT NULL) != 1
                """), 0)
        }
    }
}
