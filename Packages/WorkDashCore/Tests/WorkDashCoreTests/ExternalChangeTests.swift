import Foundation
import GRDB
import XCTest
@testable import WorkDashCore

final class ExternalChangeTests: XCTestCase {
    func testReadOnlyPoolSeesWriteFromAnotherProcess() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("wd.sqlite")
        let writer = try StoreFactory.openReadWrite(at: url)        // like the agent: creates + migrates
        try writer.write { _ in }                                     // ensure the WAL file exists

        let reader = try ReadOnlyStore(url: url)                    // like the app

        let lock = NSLock(); var counts: [Int] = []
        let cancellable = reader.observe(
            ValueObservation.tracking { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM live_items") ?? 0 },
            scheduling: .async(onQueue: .global()),
            onError: { XCTFail("\($0)") },
            onChange: { c in lock.lock(); counts.append(c); lock.unlock() })
        defer { cancellable.cancel() }

        func waitFor(_ n: Int, _ timeout: TimeInterval = 3) -> Bool {
            let end = Date().addingTimeInterval(timeout)
            while Date() < end {
                lock.lock(); let last = counts.last; lock.unlock()
                if last == n { return true }
                Thread.sleep(forTimeInterval: 0.05)
            }
            return false
        }
        XCTAssertTrue(waitFor(0), "initial value")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [url.path, "INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, body) VALUES ('x', '2026-10-27 12:00:00.000', '2026-10-27 12:00:00.000', 'agent:test', 'task', 'External', '');"]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        XCTAssertTrue(waitFor(1), "external write must reach the read-only observation")
        XCTAssertEqual(try reader.read { try String.fetchOne($0, sql: "SELECT title FROM items WHERE id = 'x'") }, "External")
        // No write API exists on ReadOnlyStore (compile-time guarantee), so there's nothing to assert at runtime.
    }

    func testOpenReadOnlyFailsWhenDatabaseMissing() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).sqlite")
        XCTAssertThrowsError(try ReadOnlyStore(url: url)) { error in
            XCTAssertEqual(error as? StoreError, .databaseMissing(url.path))
        }
    }
}
