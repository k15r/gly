import GRDB
import XCTest
@testable import WorkDashCore

final class CommandTests: XCTestCase {
    let me = "user@mac"
    var db: DatabaseQueue!
    var handler: CommandHandler!
    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        handler = CommandHandler(writer: db)
    }

    @discardableResult
    func ok(_ c: Command, writer: String? = nil, file: StaticString = #filePath, line: UInt = #line) -> CommandOK {
        switch handler.perform(c, writer: writer ?? me) {
        case .ok(let r): return r
        case .failure(let f): XCTFail("unexpected failure \(f)", file: file, line: line); return CommandOK()
        }
    }
    func failure(_ c: Command) -> CommandFailure? {
        if case .failure(let f) = handler.perform(c, writer: me) { return f }
        return nil
    }
    func row(_ id: String) throws -> Row { try db.read { try Row.fetchOne($0, sql: "SELECT * FROM items WHERE id = ?", arguments: [id])! } }
    func tags(_ id: String) throws -> [String] {
        try db.read { try String.fetchAll($0, sql: "SELECT t.name FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE it.item_id = ? ORDER BY t.name_key", arguments: [id]) }
    }
    func batches() throws -> Int { try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT batch) FROM change_log")! } }

    func testCreateMinimalTask() throws {
        let id = ok(.createTask(TaskDraft(title: "  Approve load-test budget "))).id!
        let r = try row(id)
        XCTAssertEqual(r["title"] as String, "Approve load-test budget")
        XCTAssertEqual(r["status"] as String, "open")
        XCTAssertEqual(r["priority"] as String, "none")
        XCTAssertNil(r["due_day"] as String?)
        XCTAssertEqual(try tags(id), [])
        XCTAssertEqual(r["modified_by"] as String, me)
        XCTAssertEqual(try batches(), 1)
    }

    func testCreateWithTagsAndDueIsOneBatch() throws {
        let id = ok(.createTask(TaskDraft(title: "Prep", priority: .high, due: Due(day: "2026-10-30", time: "14:00"),
                                          tags: ["person/alex", "project/atlas"]))).id!
        XCTAssertEqual(try tags(id), ["person/alex", "project/atlas"])
        XCTAssertEqual(try row(id)["due_time"] as String, "14:00")
        XCTAssertEqual(try batches(), 1, "task, tags and assignments in one undo step")
    }

    func testValidationErrors() {
        XCTAssertEqual(failure(.createTask(TaskDraft(title: "   ")))?.code, .validation)
        XCTAssertEqual(failure(.createTask(TaskDraft(title: "x", due: Due(day: "2026-02-30"))))?.code, .validation)
        XCTAssertEqual(failure(.createTask(TaskDraft(title: "x", due: Due(day: "2026-10-30", time: "25:00"))))?.code, .validation)
        XCTAssertEqual(failure(.createTask(TaskDraft(title: "x", due: Due(day: "2026-10-30", time: "9:00"))))?.code, .validation)
        XCTAssertEqual(failure(.createTask(TaskDraft(title: "x", tags: ["a//b"])))?.code, .validation)
        XCTAssertEqual(failure(.updateTask(id: "missing", TaskPatch(title: "x")))?.code, .notFound)
        XCTAssertEqual(failure(.setStatus(id: "missing", .done))?.code, .notFound)
        XCTAssertEqual(failure(.reconcileSnoozes(today: "tomorrow"))?.code, .validation)
        XCTAssertEqual(try batches(), 0, "failed commands write nothing")
    }

    func testSnoozeNeedsADate() throws {
        let id = ok(.createTask(TaskDraft(title: "T"))).id!
        XCTAssertEqual(failure(.setStatus(id: id, .snoozed))?.code, .validation)
    }

    func testUpdateOnlyChangesGivenFieldsAndClearsDue() throws {
        let id = ok(.createTask(TaskDraft(title: "T", priority: .low, due: Due(day: "2026-10-30")))).id!
        XCTAssertTrue(ok(.updateTask(id: id, TaskPatch(priority: .urgent))).changed)
        XCTAssertEqual(try row(id)["priority"] as String, "urgent")
        XCTAssertEqual(try row(id)["due_day"] as String, "2026-10-30", "untouched")
        ok(.updateTask(id: id, TaskPatch(due: .some(nil))))
        XCTAssertNil(try row(id)["due_day"] as String?)
        XCTAssertFalse(ok(.updateTask(id: id, TaskPatch(priority: .urgent))).changed, "no-op update")
    }

    func testStatusTransitions() throws {
        let id = ok(.createTask(TaskDraft(title: "T"))).id!
        ok(.setStatus(id: id, .done))
        XCTAssertNotNil(try row(id)["completed_at"] as Date?)
        ok(.setStatus(id: id, .open))
        XCTAssertNil(try row(id)["completed_at"] as Date?)
        ok(.setStatus(id: id, .snoozed, snoozedUntil: "2026-11-02"))
        XCTAssertEqual(try row(id)["snoozed_until"] as String, "2026-11-02")
        ok(.setStatus(id: id, .dropped))
        XCTAssertEqual(try row(id)["status"] as String, "dropped")
        XCTAssertNil(try row(id)["snoozed_until"] as String?)
    }

    func testDeleteAndUndoThroughCommands() throws {
        let id = ok(.createTask(TaskDraft(title: "T", tags: ["person/alex"]))).id!
        ok(.deleteTask(id: id))
        XCTAssertNotNil(try row(id)["deleted_at"] as Date?)
        XCTAssertEqual(failure(.setStatus(id: id, .done))?.code, .notFound, "deleted tasks can't be edited")
        XCTAssertTrue(ok(.undo).changed)
        XCTAssertNil(try row(id)["deleted_at"] as Date?)
        XCTAssertEqual(try tags(id), ["person/alex"])
        XCTAssertTrue(ok(.redo).changed)
        XCTAssertNotNil(try row(id)["deleted_at"] as Date?)
    }

    func testUndoWithNothingToUndo() {
        let r = ok(.undo)
        XCTAssertFalse(r.changed)
        XCTAssertEqual(r.message, "Nothing to undo.")
    }

    func testSetTagsDiffsAndReusesTagWithDifferentCasing() throws {
        let a = ok(.createTask(TaskDraft(title: "A", tags: ["Person/Alex"]))).id!
        let b = ok(.createTask(TaskDraft(title: "B"))).id!
        ok(.setTags(id: b, ["person/alex", "project/atlas"]))
        XCTAssertEqual(try tags(b), ["Person/Alex", "project/atlas"], "existing tag reused with its first casing")
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM live_tags") }, 2, "no second tag created")
        ok(.setTags(id: b, ["project/atlas"]))
        XCTAssertEqual(try tags(b), ["project/atlas"])
        XCTAssertEqual(try tags(a), ["Person/Alex"], "tag still exists for other tasks")
        XCTAssertFalse(ok(.setTags(id: b, ["Project/Atlas"])).changed, "same set, different casing = no change")
    }

    func testReconcileSnoozesReopensDueTasks() throws {
        let past = ok(.createTask(TaskDraft(title: "past"))).id!
        let future = ok(.createTask(TaskDraft(title: "future"))).id!
        ok(.setStatus(id: past, .snoozed, snoozedUntil: "2026-10-27"))
        ok(.setStatus(id: future, .snoozed, snoozedUntil: "2026-11-01"))
        let r = ok(.reconcileSnoozes(today: "2026-10-27"), writer: "system@mac")
        XCTAssertEqual(r.message, "1 snoozed task(s) reopened")
        XCTAssertEqual(try row(past)["status"] as String, "open")
        XCTAssertNil(try row(past)["snoozed_until"] as String?)
        XCTAssertEqual(try row(past)["modified_by"] as String, "system@mac")
        XCTAssertEqual(try row(future)["status"] as String, "snoozed")
    }

    func testCommandsAreCodable() throws {
        let commands: [Command] = [.ping, .createTask(TaskDraft(title: "T", due: Due(day: "2026-10-30"), tags: ["a/b"])),
                                   .updateTask(id: "i", TaskPatch(due: .some(nil))), .setStatus(id: "i", .snoozed, snoozedUntil: "2026-11-01"),
                                   .deleteTask(id: "i"), .setTags(id: "i", ["x"]), .undo, .redo, .reconcileSnoozes(today: "2026-10-27")]
        for c in commands {
            XCTAssertEqual(try JSONDecoder().decode(Command.self, from: JSONEncoder().encode(c)), c)
        }
        let result = CommandResult.failure(CommandFailure(.validation, "x"))
        XCTAssertEqual(try JSONDecoder().decode(CommandResult.self, from: JSONEncoder().encode(result)), result)
    }
}

extension CommandTests {
    func testReloadSettingsAndAgentStatusDontWrite() throws {
        XCTAssertFalse(ok(.reloadSettings).changed)
        XCTAssertFalse(ok(.agentStatus).changed)
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM change_log") }, 0)
    }
}
