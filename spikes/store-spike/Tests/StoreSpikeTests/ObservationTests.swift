import Foundation
import GRDB
import XCTest
@testable import StoreSpike

final class ObservationTests: XCTestCase {
    /// Does ValueObservation on a DatabasePool see a write from ANOTHER process (sqlite3 CLI)?
    func testObservationAndExternalProcessWrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("wd.sqlite").path
        let pool = try DatabasePool(path: path)
        try Schema.migrator.migrate(pool)

        var counts: [Int] = []
        let lock = NSLock()
        let obs = ValueObservation.tracking { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items") ?? 0 }
        let cancellable = obs.start(in: pool, scheduling: .async(onQueue: .global()),
                                    onError: { XCTFail("\($0)") },
                                    onChange: { c in lock.lock(); counts.append(c); lock.unlock() })
        defer { cancellable.cancel() }

        func waitForCount(_ n: Int, timeout: TimeInterval) -> Bool {
            let end = Date().addingTimeInterval(timeout)
            while Date() < end {
                lock.lock(); let last = counts.last; lock.unlock()
                if last == n { return true }
                Thread.sleep(forTimeInterval: 0.05)
            }
            return false
        }
        XCTAssertTrue(waitForCount(0, timeout: 2), "initial value")

        // 1. Same-process write through the pool -> must be observed.
        try pool.write { try $0.insert("items", ["kind": "info", "title": "in-process"], by: Writer("user@mac")) }
        XCTAssertTrue(waitForCount(1, timeout: 2), "in-process write observed")

        // 2. Write from another process (sqlite3 CLI).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [path, "INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, body) VALUES ('ext1', '2026-10-25 12:00:00.000', '2026-10-25 12:00:00.000', 'agent:cli', 'info', 'external', '');"]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        let externalSeen = waitForCount(2, timeout: 3)
        print("OBSERVATION external-process write observed by ValueObservation: \(externalSeen)")
        print("OBSERVATION actual row count now: \(try pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM live_items")! })")
        XCTAssertFalse(externalSeen, "documents GRDB behaviour: other-process writes are not observed by default")

        // 3. With the WAL watcher + notifyChanges, the next external write is observed.
        let watcher = try ExternalChangeWatcher(pool: pool, path: path)
        defer { _ = watcher }
        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p2.arguments = [path, "INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, body) VALUES ('ext2', '2026-10-25 12:00:00.000', '2026-10-25 12:00:00.000', 'agent:cli', 'info', 'external 2', '');"]
        let t0 = Date()
        try p2.run(); p2.waitUntilExit()
        let seen = waitForCount(3, timeout: 3)
        print(String(format: "OBSERVATION with watcher: observed=%@ after %.0f ms", seen ? "true" : "false", Date().timeIntervalSince(t0) * 1000))
        XCTAssertTrue(seen, "external write must be observed with the watcher")
    }
}
