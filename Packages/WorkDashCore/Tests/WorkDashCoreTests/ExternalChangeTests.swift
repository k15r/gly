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

    /// The WAL event often arrives while the writer still holds its lock (mid-commit). The notification must wait
    /// for the lock instead of failing silently; otherwise the app misses the change (found: a deleted page stayed in the tag tree).
    func testNotifyWhileWriterHoldsLockStillDelivers() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("wd.sqlite")
        let writer = try StoreFactory.openReadWrite(at: url)
        try writer.write { _ in }
        let pool = try DatabasePool(path: url.path, configuration: ReadOnlyStore.configuration)

        let lock = NSLock(); var last: Int?
        let cancellable = ValueObservation.tracking { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM live_items") ?? 0 }
            .start(in: pool, scheduling: .async(onQueue: .global()), onError: { XCTFail("\($0)") },
                   onChange: { c in lock.lock(); last = c; lock.unlock() })
        defer { cancellable.cancel() }
        func waitFor(_ n: Int) -> Bool {
            let end = Date().addingTimeInterval(3)
            while Date() < end { lock.lock(); let l = last; lock.unlock(); if l == n { return true }; Thread.sleep(forTimeInterval: 0.05) }
            return false
        }
        XCTAssertTrue(waitFor(0))

        let holding = expectation(description: "writer holds the lock")
        let done = expectation(description: "writer committed")
        DispatchQueue.global().async {
            try? writer.write { db in
                try db.execute(sql: "INSERT INTO items (id, created_at, modified_at, modified_by, kind, title, body) VALUES ('x', '2026-10-27 12:00:00.000', '2026-10-27 12:00:00.000', 'agent:test', 'task', 'T', '')")
                holding.fulfill()
                Thread.sleep(forTimeInterval: 0.4)
            }
            done.fulfill()
        }
        wait(for: [holding], timeout: 2)
        ExternalChangeWatcher.notify(pool)          // the only notification, sent while the lock is held
        wait(for: [done], timeout: 2)
        XCTAssertTrue(waitFor(1), "the observation must see the committed row")
    }

    func testOpenReadOnlyFailsWhenDatabaseMissing() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).sqlite")
        XCTAssertThrowsError(try ReadOnlyStore(url: url)) { error in
            XCTAssertEqual(error as? StoreError, .databaseMissing(url.path))
        }
    }
}
