import GRDB
import XCTest
@testable import WorkDashCore

final class TaskQueryTests: XCTestCase {
    var db: DatabaseQueue!
    let today = LocalDay("2026-10-27")!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory() }
    func t(_ minutes: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60) }

    func testDefaultSortingScenario() throws {
        // specs/tasks: urgent without due, normal due tomorrow, normal due today -> urgent, today, tomorrow
        try db.write { db in
            try addTask(db, "normal tomorrow", priority: "normal", dueDay: "2026-10-28", createdAt: t(1))
            try addTask(db, "urgent no due", priority: "urgent", createdAt: t(2))
            try addTask(db, "normal today", priority: "normal", dueDay: "2026-10-27", createdAt: t(3))
            try addTask(db, "none no due", createdAt: t(4))
            try addTask(db, "normal no due", priority: "normal", createdAt: t(0))
            XCTAssertEqual(try TaskQueries.taskList(db, mode: .open, today: today).map(\.title),
                           ["urgent no due", "normal today", "normal tomorrow", "normal no due", "none no due"])
        }
    }

    func testWholeDayBeforeTimedOnSameDay() throws {
        try db.write { db in
            try addTask(db, "timed", priority: "high", dueDay: "2026-10-27", dueTime: "09:00", createdAt: t(0))
            try addTask(db, "whole day", priority: "high", dueDay: "2026-10-27", createdAt: t(1))
            XCTAssertEqual(try TaskQueries.taskList(db, mode: .open, today: today).map(\.title), ["whole day", "timed"])
        }
    }

    func testOpenListIncludesSnoozedInNormalOrder() throws {
        try db.write { db in
            try addTask(db, "open")
            try addTask(db, "snooze arrived", status: "snoozed", snoozedUntil: "2026-10-27")
            try addTask(db, "snooze later", status: "snoozed", snoozedUntil: "2026-10-30")
            try addTask(db, "snooze latest urgent", status: "snoozed", priority: "urgent", snoozedUntil: "2026-10-31")
            try addTask(db, "done", status: "done")
            try addTask(db, "dropped", status: "dropped")
            let list = try TaskQueries.taskList(db, mode: .open, today: today)
            XCTAssertEqual(list.first?.title, "snooze latest urgent", "sorted by priority like any task")
            XCTAssertEqual(Set(list.map(\.title)), ["open", "snooze arrived", "snooze later", "snooze latest urgent"])
            XCTAssertEqual(Set(list.filter { $0.isSnoozed(today: today) }.map(\.title)), ["snooze later", "snooze latest urgent"])
            XCTAssertEqual(try TaskQueries.taskList(db, mode: .dropped, today: today).map(\.title), ["dropped"])
        }
    }

    func testDoneListMostRecentlyCompletedFirst() throws {
        let h = CommandHandler(writer: db)
        func create(_ title: String) -> String { if case .ok(let r) = h.perform(.createTask(TaskDraft(title: title)), writer: "u") { return r.id! }; return "" }
        let a = create("first done"), b = create("second done")
        _ = h.perform(.setStatus(id: a, .done), writer: "u", now: t(10))
        _ = h.perform(.setStatus(id: b, .done), writer: "u", now: t(20))
        try db.read { db in
            XCTAssertEqual(try TaskQueries.taskList(db, mode: .done, today: today).map(\.title), ["second done", "first done"])
        }
    }

    func testTagFilterInTaskList() throws {
        try db.write { db in
            try addTask(db, "atlas", tags: ["project/atlas"])
            try addTask(db, "atlas logs", tags: ["project/atlas/logs"])
            try addTask(db, "other", tags: ["person/alex"])
            let list = try TaskQueries.taskList(db, mode: .open, today: today, tag: try TagName("project"))
            XCTAssertEqual(Set(list.map(\.title)), ["atlas", "atlas logs"])
            XCTAssertEqual(list.first { $0.title == "atlas logs" }?.tags, ["project/atlas/logs"])
        }
    }

    func testDueAndOverdueTasksTodayScenario() throws {
        // specs/day-view: urgent due today, normal due today, normal due yesterday (open)
        try db.write { db in
            try addTask(db, "normal today", priority: "normal", dueDay: "2026-10-27", createdAt: t(1))
            try addTask(db, "urgent today", priority: "urgent", dueDay: "2026-10-27", createdAt: t(2))
            try addTask(db, "normal yesterday", priority: "normal", dueDay: "2026-10-26", createdAt: t(3))
            try addTask(db, "done yesterday", status: "done", priority: "urgent", dueDay: "2026-10-26")
            try addTask(db, "no due", priority: "urgent")
            let day = try TaskQueries.tasksForDay(db, day: today, today: today)
            XCTAssertEqual(day.map(\.task.title), ["urgent today", "normal yesterday", "normal today"])
            XCTAssertEqual(day.map(\.isOverdue), [false, true, false])
        }
    }

    func testFutureDayScenarioHasNoOverdue() throws {
        try db.write { db in
            try addTask(db, "yesterday", dueDay: "2026-10-26")
            try addTask(db, "tomorrow", dueDay: "2026-10-28")
            let day = try TaskQueries.tasksForDay(db, day: today.adding(days: 1), today: today)
            XCTAssertEqual(day.map(\.task.title), ["tomorrow"])
            XCTAssertFalse(day[0].isOverdue)
        }
    }

    func testSnoozedUntilTomorrowScenario() throws {
        // specs/day-view: a task due today, snoozed until tomorrow, is in no day view until tomorrow is today; then it's overdue.
        let h = CommandHandler(writer: db)
        guard case .ok(let r) = h.perform(.createTask(TaskDraft(title: "B", due: Due(day: "2026-10-27"))), writer: "u") else { return XCTFail() }
        _ = h.perform(.setStatus(id: r.id!, .snoozed, snoozedUntil: "2026-10-28"), writer: "u")
        let nextDay = today.adding(days: 1)
        try db.read { db in
            XCTAssertTrue(try TaskQueries.tasksForDay(db, day: today, today: today).isEmpty, "gone today")
            XCTAssertTrue(try TaskQueries.tasksForDay(db, day: nextDay, today: today).isEmpty, "not shown on a future day")
            // Still a regular entry of the task list, marked snoozed.
            let list = try TaskQueries.taskList(db, mode: .open, today: today)
            XCTAssertEqual(list.map(\.title), ["B"])
            XCTAssertTrue(list[0].isSnoozed(today: today))
        }
        _ = h.perform(.reconcileSnoozes(today: nextDay.description), writer: "system@test")
        try db.read { db in
            let d = try TaskQueries.tasksForDay(db, day: nextDay, today: nextDay)
            XCTAssertEqual(d.map(\.task.title), ["B"])
            XCTAssertEqual(d.map(\.isOverdue), [true])
        }
    }

    func testSnoozedTaskWithoutDueDateNeverInDayView() throws {
        try db.write { db in
            try addTask(db, "no due", status: "snoozed", snoozedUntil: "2026-10-29")
            XCTAssertTrue(try TaskQueries.tasksForDay(db, day: LocalDay("2026-10-29")!, today: today).isEmpty)
        }
    }

    func testSnoozedTaskAppearsFromItsSnoozeDate() throws {
        try db.write { db in
            try addTask(db, "snoozed", status: "snoozed", dueDay: "2026-10-29", snoozedUntil: "2026-10-29")
            XCTAssertTrue(try TaskQueries.tasksForDay(db, day: LocalDay("2026-10-28")!, today: today).isEmpty)
            XCTAssertEqual(try TaskQueries.tasksForDay(db, day: LocalDay("2026-10-29")!, today: today).map(\.task.title), ["snoozed"])
        }
    }
}
