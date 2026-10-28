import GRDB
import XCTest
@testable import GlyCore

/// task-progress P1, P2: specs/tasks "Remaining effort", "Progress on the task page".
final class TaskProgressTests: XCTestCase {
    let me = "user@mac"
    var db: DatabaseQueue!
    var h: CommandHandler!
    let sizes = EffortSizes.defaults(for: WorkingHours())     // L = 480, XL = 1440
    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        h = CommandHandler(writer: db)
    }

    func newTask(effort: Effort?) -> String {
        guard case .ok(let r) = h.perform(.createTask(TaskDraft(title: "Report", due: Due(day: "2026-11-03"), effort: effort)), writer: me),
              let id = r.id else { XCTFail("create failed"); return "" }
        return id
    }
    func task(_ id: String) throws -> TaskItem { try XCTUnwrap(try db.read { try TaskQueries.task($0, id: id) }) }
    func remaining(_ id: String) throws -> Int? { try task(id).remaining(sizes: sizes) }
    @discardableResult func run(_ c: Command) -> CommandResult { h.perform(c, writer: me) }

    func testMigrationAddsTheTable() throws {
        XCTAssertTrue(try db.read { try $0.tableExists("task_work") })
        XCTAssertTrue(Schema.syncedTables.contains("task_work"))
    }

    func testRecordedWorkReducesTheRemainingEffort() throws {
        let id = newTask(effort: .xl)
        XCTAssertEqual(try remaining(id), 1440)
        run(.recordWork(id: id, day: "2026-10-28", minutes: 480, kind: .part))
        XCTAssertEqual(try task(id).workedMinutes, 480)
        XCTAssertEqual(try remaining(id), 960)
    }

    func testSetWhatsLeft() throws {
        // specs/tasks "Set what's left": XL, set to 1 day 4 hours → recorded 1d 4h as an adjustment for today.
        let id = newTask(effort: .xl)
        run(.setRemaining(id: id, minutes: 720, effortMinutes: 1440, day: "2026-10-28"))
        XCTAssertEqual(try remaining(id), 720)
        XCTAssertEqual(try db.read { try TaskQueries.work($0, taskID: id) }, [WorkEntry(day: "2026-10-28", kind: .adjust, minutes: 720)])
    }

    func testMoreLeftThanThought() throws {
        // specs/tasks "More left than thought": L with 4 h left, set to 6 h → adjustment of −2 h.
        let id = newTask(effort: .l)
        run(.recordWork(id: id, day: "2026-10-27", minutes: 240, kind: .part))
        run(.setRemaining(id: id, minutes: 360, effortMinutes: 480, day: "2026-10-28"))
        XCTAssertEqual(try remaining(id), 360)
        XCTAssertEqual(try db.read { try TaskQueries.work($0, taskID: id) }.first, WorkEntry(day: "2026-10-28", kind: .adjust, minutes: -120))
    }

    func testEffortChangedLater() throws {
        // specs/tasks "Effort changed later": XL with 1 day recorded, effort → L: remaining 0, work kept.
        let id = newTask(effort: .xl)
        run(.recordWork(id: id, day: "2026-10-28", minutes: 480, kind: .part))
        run(.updateTask(id: id, TaskPatch(effort: .some(.l))))
        XCTAssertEqual(try remaining(id), 0)
        XCTAssertEqual(try task(id).workedMinutes, 480)
    }

    func testNeverBelowZeroAndNilWithoutEffort() throws {
        let id = newTask(effort: .s)
        run(.recordWork(id: id, day: "2026-10-28", minutes: 600, kind: .agent))
        XCTAssertEqual(try remaining(id), 0)
        XCTAssertNil(try remaining(newTask(effort: nil)))
    }

    func testResetAndUndo() throws {
        // specs/tasks "Reset": back to the full effort; undo brings the work back.
        let id = newTask(effort: .xl)
        run(.recordWork(id: id, day: "2026-10-27", minutes: 480, kind: .part))
        run(.setRemaining(id: id, minutes: 600, effortMinutes: 1440, day: "2026-10-28"))
        run(.resetRemaining(id: id))
        XCTAssertEqual(try remaining(id), 1440)
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Reset progress of “Report”")
        run(.undo)
        XCTAssertEqual(try remaining(id), 600)
    }

    func testTakeBackTodaysPart() throws {
        let id = newTask(effort: .xl)
        run(.recordWork(id: id, day: "2026-10-27", minutes: 480, kind: .part))
        run(.recordWork(id: id, day: "2026-10-28", minutes: 480, kind: .part))
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Record work on “Report”")
        run(.undoTodaysPart(id: id, day: "2026-10-28"))
        XCTAssertEqual(try remaining(id), 960, "only that day's part is taken back")
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Take back today's part of “Report”")
        run(.undo)
        XCTAssertEqual(try remaining(id), 480)
    }

    func testUndoOfRecordAndSet() throws {
        let id = newTask(effort: .xl)
        run(.setRemaining(id: id, minutes: 600, effortMinutes: 1440, day: "2026-10-28"))
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Set remaining effort of “Report”")
        run(.undo)
        XCTAssertEqual(try remaining(id), 1440)
        run(.recordWork(id: id, day: "2026-10-28", minutes: 120, kind: .part))
        run(.undo)
        XCTAssertEqual(try task(id).workedMinutes, 0)
    }

    func testNegativeRemainingIsRejected() throws {
        let id = newTask(effort: .l)
        guard case .failure(let f) = run(.setRemaining(id: id, minutes: -1, effortMinutes: 480, day: "2026-10-28")) else { return XCTFail() }
        XCTAssertEqual(f.code, .validation)
    }

    func testEraseAllDataClearsWork() throws {
        let id = newTask(effort: .l)
        run(.recordWork(id: id, day: "2026-10-28", minutes: 60, kind: .part))
        run(.eraseAllData)
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM task_work") }, 0)
    }
}
