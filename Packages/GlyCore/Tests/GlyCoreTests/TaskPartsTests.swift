import GRDB
import XCTest
@testable import GlyCore

/// subtasks S1–S4: specs/tasks "Parts of a task", "All parts done", "Search finds parts";
/// specs/daily-planning "Remaining effort from parts".
final class TaskPartsTests: XCTestCase {
    let me = "user@mac"
    var db: DatabaseQueue!
    var h: CommandHandler!
    let sizes = EffortSizes.defaults(for: WorkingHours())     // S = 120, L = 480
    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        h = CommandHandler(writer: db)
    }

    func newTask(effort: Effort? = nil) -> String {
        guard case .ok(let r) = h.perform(.createTask(TaskDraft(title: "Report", effort: effort)), writer: me), let id = r.id else {
            XCTFail("create failed"); return ""
        }
        return id
    }
    @discardableResult func add(_ task: String, _ title: String, _ effort: Effort? = nil) -> String {
        guard case .ok(let r) = h.perform(.addPart(taskID: task, title: title, effort: effort), writer: me), let id = r.id else {
            XCTFail("add failed"); return ""
        }
        return id
    }
    func task(_ id: String) throws -> TaskItem { try XCTUnwrap(try db.read { try TaskQueries.task($0, id: id) }) }
    func titles(_ id: String) throws -> [String] { try task(id).parts.map(\.title) }
    func label() throws -> String? { try db.read { try $0.undoLabel(writer: me) } }

    func testMigrationAddsTheTable() throws {
        XCTAssertTrue(try db.read { try $0.tableExists("task_parts") })
        XCTAssertTrue(Schema.syncedTables.contains("task_parts"))
    }

    func testBreakATaskDown() throws {
        // "Break a task down": in order, none done yet.
        let t = newTask()
        add(t, "Outline", .s); add(t, "Draft", .l); add(t, "Review", .s)
        XCTAssertEqual(try titles(t), ["Outline", "Draft", "Review"])
        XCTAssertEqual(try task(t).parts.filter(\.done).count, 0)
        XCTAssertEqual(try label(), "Add part “Review” to “Report”")
    }

    func testEditTickOffAndDeleteWithUndo() throws {
        let t = newTask()
        let p = add(t, "Draft", .l)
        _ = h.perform(.updatePart(id: p, PartPatch(title: "First draft", effort: .some(.m))), writer: me)
        XCTAssertEqual(try task(t).parts.first?.title, "First draft")
        XCTAssertEqual(try task(t).parts.first?.effort, .m)
        XCTAssertEqual(try label(), "Edit part “First draft”")
        _ = h.perform(.updatePart(id: p, PartPatch(done: true)), writer: me)
        XCTAssertEqual(try task(t).parts.first?.done, true)
        XCTAssertEqual(try label(), "Tick off “First draft”")
        _ = h.perform(.undo, writer: me)
        XCTAssertEqual(try task(t).parts.first?.done, false)
        _ = h.perform(.deletePart(id: p), writer: me)
        XCTAssertEqual(try titles(t), [])
        XCTAssertEqual(try label(), "Remove part “First draft”")
        _ = h.perform(.undo, writer: me)
        XCTAssertEqual(try titles(t), ["First draft"])
    }

    func testMoveBetweenTwoParts() throws {
        let t = newTask()
        add(t, "A"); add(t, "B"); let c = add(t, "C")
        _ = h.perform(.movePart(id: c, toIndex: 1), writer: me)
        XCTAssertEqual(try titles(t), ["A", "C", "B"])
        XCTAssertEqual(try label(), "Move part “C”")
        _ = h.perform(.movePart(id: c, toIndex: 0), writer: me)
        XCTAssertEqual(try titles(t), ["C", "A", "B"])
        _ = h.perform(.movePart(id: c, toIndex: 9), writer: me)
        XCTAssertEqual(try titles(t), ["A", "B", "C"])
        _ = h.perform(.undo, writer: me)
        XCTAssertEqual(try titles(t), ["C", "A", "B"])
    }

    func testReplacePartsKeepsAddsAndRemovesByID() throws {
        let t = newTask()
        let a = add(t, "A", .s); let b = add(t, "B"); add(t, "C")
        _ = h.perform(.replaceParts(taskID: t, [PartInput(id: b, title: "B2", done: true), PartInput(title: "D", effort: .xs),
                                            PartInput(id: a, title: "A", effort: .s)]), writer: me)
        let parts = try task(t).parts
        XCTAssertEqual(parts.map(\.title), ["B2", "D", "A"])
        XCTAssertEqual(parts.map(\.done), [true, false, false])
        XCTAssertEqual(parts.first?.id, b, "kept by id")
        XCTAssertEqual(try label(), "Change parts of “Report”")
        _ = h.perform(.undo, writer: me)
        XCTAssertEqual(try titles(t), ["A", "B", "C"], "one step")
        guard case .failure(let f) = h.perform(.replaceParts(taskID: t, [PartInput(id: "nope", title: "X")]), writer: me) else { return XCTFail() }
        XCTAssertEqual(f.code, .notFound)
    }

    func testCreateTaskWithParts() throws {
        guard case .ok(let r) = h.perform(.createTask(TaskDraft(title: "Trip", parts: [PartInput(title: "Book"), PartInput(title: "Pack", effort: .s)])),
                                          writer: me), let t = r.id else { return XCTFail() }
        XCTAssertEqual(try titles(t), ["Book", "Pack"])
    }

    func testFindByPart() throws {
        // "Find by part": search shows the task.
        let t = newTask()
        add(t, "Draft chapter")
        let results = try db.read { try SearchQueries.search($0, "chapter") }
        XCTAssertTrue(results.all.contains { $0.id == t }, "\(results)")
        _ = h.perform(.undo, writer: me)
        XCTAssertFalse(try db.read { try SearchQueries.search($0, "chapter") }.all.contains { $0.id == t }, "removed with the part")
    }

    func testTickingOffAPart() throws {
        // "Ticking off a part": Outline S, Draft L, Review S → tick Outline → 1 day 2 hours.
        let t = newTask(effort: .xl)
        let outline = add(t, "Outline", .s); add(t, "Draft", .l); add(t, "Review", .s)
        XCTAssertEqual(try task(t).remaining(sizes: sizes), 120 + 480 + 120)
        _ = h.perform(.updatePart(id: outline, PartPatch(done: true)), writer: me)
        XCTAssertEqual(try task(t).remaining(sizes: sizes), 480 + 120)
        XCTAssertTrue(try task(t).hasEstimatedParts)
    }

    func testUnestimatedParts() throws {
        // "Unestimated parts": the task's own effort and recorded work stay in charge.
        let t = newTask(effort: .l)
        add(t, "One"); add(t, "Two")
        _ = h.perform(.recordWork(id: t, day: "2026-10-28", minutes: 60, kind: .part), writer: me)
        XCTAssertFalse(try task(t).hasEstimatedParts)
        XCTAssertEqual(try task(t).remaining(sizes: sizes), 420)
    }

    func testAllPartsDoneLeavesTheTaskOpen() throws {
        let t = newTask()
        let p = add(t, "Only")
        _ = h.perform(.updatePart(id: p, PartPatch(done: true)), writer: me)
        XCTAssertEqual(try task(t).status, .open)
    }
}
