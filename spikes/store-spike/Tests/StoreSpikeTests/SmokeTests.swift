import GRDB
import XCTest
@testable import StoreSpike

final class SmokeTests: XCTestCase {
    func testOpensInMemoryDatabaseWithFTS5() throws {
        let store = try Store()
        try store.db.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT 1"), 1)
            // FTS5 is required by D3; fail early if the system SQLite lacks it.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT sqlite_compileoption_used('ENABLE_FTS5')"), 1)
        }
    }
}
