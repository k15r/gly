import GRDB
import XCTest
@testable import GlyCore

/// future-day-planning F3: the day a task comes back from a snooze, for the "back from snooze" mark.
final class SnoozeReturnTests: XCTestCase {
    let me = "user@mac"
    var db: DatabaseQueue!
    var h: CommandHandler!
    let today = LocalDay("2026-10-27")!
    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        h = CommandHandler(writer: db)
    }

    func snoozedTask(until day: String) -> String {
        guard case .ok(let r) = h.perform(.createTask(TaskDraft(title: "Report", due: Due(day: "2026-10-30"))), writer: me),
              let id = r.id else { XCTFail("create failed"); return "" }
        _ = h.perform(.setStatus(id: id, .snoozed, snoozedUntil: day), writer: me)
        return id
    }
    func task(_ id: String) throws -> TaskItem { try XCTUnwrap(try db.read { try TaskQueries.task($0, id: id) }) }
    func ended(_ id: String) throws -> String? {
        try db.read { try String.fetchOne($0, sql: "SELECT snooze_ended_on FROM items WHERE id = ?", arguments: [id]) }
    }

    func testMigrationAddsTheColumn() throws {
        let columns = try db.read { try $0.columns(in: "items").map(\.name) }
        XCTAssertTrue(columns.contains("snooze_ended_on"))
    }

    func testWakingRecordsTheScheduledReturnDay() throws {
        let id = snoozedTask(until: "2026-10-27")
        _ = h.perform(.reconcileSnoozes(today: "2026-10-29"), writer: "system@test")    // app wasn't running on the 27th
        let t = try task(id)
        XCTAssertEqual(t.status, .open)
        XCTAssertNil(t.snoozedUntil)
        XCTAssertEqual(t.snoozeEndedOn, "2026-10-27")
        XCTAssertTrue(t.isBackFromSnooze(on: today))
        XCTAssertFalse(t.isBackFromSnooze(on: LocalDay("2026-10-29")!), "only on its snooze date")
        XCTAssertEqual(t.snoozeReturnDay, "2026-10-27")
    }

    func testUserStatusChangesClearIt() throws {
        for change in [TaskStatus.done, .dropped, .snoozed, .open] {
            let id = snoozedTask(until: "2026-10-27")
            _ = h.perform(.reconcileSnoozes(today: "2026-10-27"), writer: "system@test")
            XCTAssertEqual(try ended(id), "2026-10-27")
            _ = h.perform(.setStatus(id: id, change, snoozedUntil: change == .snoozed ? "2026-11-02" : nil), writer: me)
            XCTAssertNil(try ended(id), "\(change)")
        }
    }

    func testUndoRestoresIt() throws {
        let id = snoozedTask(until: "2026-10-27")
        _ = h.perform(.reconcileSnoozes(today: "2026-10-27"), writer: "system@test")
        _ = h.perform(.setStatus(id: id, .done, snoozedUntil: nil), writer: me)
        XCTAssertNil(try ended(id))
        _ = h.perform(.undo, writer: me)
        XCTAssertEqual(try ended(id), "2026-10-27")
        XCTAssertEqual(try task(id).status, .open)
    }

    func testStillSnoozedCountsOnItsReturnDay() throws {
        // Not woken yet (before the midnight reconcile), or a forecast of a later day.
        let id = snoozedTask(until: "2026-10-29")
        let t = try task(id)
        XCTAssertFalse(t.isBackFromSnooze(on: today))
        XCTAssertTrue(t.isBackFromSnooze(on: LocalDay("2026-10-29")!))
        XCTAssertFalse(t.isBackFromSnooze(on: LocalDay("2026-10-30")!), "the day after shows no mark")
        XCTAssertEqual(t.snoozeReturnDay, "2026-10-29")
    }

    func testNeverSnoozedHasNoMark() throws {
        guard case .ok(let r) = h.perform(.createTask(TaskDraft(title: "Plain")), writer: me), let id = r.id else { return XCTFail() }
        XCTAssertFalse(try task(id).isBackFromSnooze(on: today))
    }
}
