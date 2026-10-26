import Foundation
import GRDB
import XCTest
@testable import WorkDashCore

final class PlanningTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }()
    let hours = WorkingHours()
    var sizes: EffortSizes { .defaults(for: hours) }
    func at(_ d: String, _ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: LocalDay(d)!.interval(in: cal).start)! }
    func task(_ title: String, due: String, time: String? = nil, effort: Effort?, priority: Priority = .none) -> TaskItem {
        TaskItem(id: title, title: title, body: "", status: .open, priority: priority, due: Due(day: due, time: time), snoozedUntil: nil,
                 tags: [], createdAt: Date(), modifiedAt: Date(), modifiedBy: "u", completedAt: nil, effort: effort)
    }

    func testDefaultSizes() {
        XCTAssertEqual(sizes[.l], 480)
        XCTAssertEqual(sizes[.xl], 1440)
        XCTAssertEqual(EffortSizes.defaults(for: WorkingHours(startMinute: 8 * 60, endMinute: 14 * 60))[.l], 360)
    }

    func testStates() {
        XCTAssertEqual(Planning.state(effortMinutes: 480, freeMinutes: 600, dueTomorrow: false), .tight)   // "Tight task"
        XCTAssertEqual(Planning.state(effortMinutes: 240, freeMinutes: 120, dueTomorrow: false), .late)    // "Late task"
        XCTAssertEqual(Planning.state(effortMinutes: 120, freeMinutes: 1200, dueTomorrow: false), .ok)     // "Plenty of time"
        XCTAssertEqual(Planning.state(effortMinutes: 120, freeMinutes: 200, dueTomorrow: false), .startToday)   // 1.5× ≤ free < 2×
        XCTAssertEqual(Planning.state(effortMinutes: 30, freeMinutes: 900, dueTomorrow: true), .startToday)
        XCTAssertEqual(Planning.state(effortMinutes: nil, freeMinutes: 900, dueTomorrow: false), .noEstimate)
    }

    func testEvaluateWithCalendar() {
        let now = at("2026-10-26", 9)   // Monday
        // Mon–Wed mostly blocked by a long blocking meeting each day, 09–15.
        let busy = ["2026-10-26", "2026-10-27", "2026-10-28"].map { (interval: DateInterval(start: at($0, 9), end: at($0, 15)), weight: BlockingWeight.blocks) }
        let items = Planning.evaluate([
            task("big", due: "2026-10-28", effort: .l),                // 3 × 2 h free = 6 h < 8 h → late
            task("today 17h", due: "2026-10-26", time: "17:00", effort: .m),  // 2 h free < 4 h → late
            task("small", due: "2026-10-30", effort: .s),              // plenty → ok
            task("unknown", due: "2026-10-29", effort: nil),
        ], now: now, sizes: sizes, hours: hours, busy: busy, calendar: cal)
        XCTAssertEqual(items.map(\.task.title), ["big", "today 17h", "small", "unknown"].sorted { a, b in
            let order = ["today 17h": 0, "big": 1, "small": 2, "unknown": 3]; return order[a]! < order[b]! })
        XCTAssertEqual(items.map(\.state), [.late, .late, .ok, .noEstimate])
        XCTAssertEqual(items.first { $0.task.title == "big" }?.freeMinutes, 360)
    }

    func testUpcomingQueryHorizonAndSnooze() throws {
        let db = try StoreFactory.openInMemory()
        try db.write { db in
            try addTask(db, "today", dueDay: "2026-10-26")
            try addTask(db, "in 4 days", dueDay: "2026-10-30")
            try addTask(db, "in 8 days", dueDay: "2026-11-03")
            try addTask(db, "snoozed until later", status: "snoozed", dueDay: "2026-10-28", snoozedUntil: "2026-10-29")
            try addTask(db, "done", status: "done", dueDay: "2026-10-27")
        }
        let today = LocalDay("2026-10-26")!
        XCTAssertEqual(try db.read { try TaskQueries.upcoming($0, today: today, horizon: 5) }.map(\.title), ["in 4 days"])
        XCTAssertEqual(try db.read { try TaskQueries.upcoming($0, today: today, horizon: 14) }.map(\.title), ["in 4 days", "in 8 days"])
        XCTAssertEqual(try db.read { try TaskQueries.upcoming($0, today: LocalDay("2026-10-27")!, horizon: 5) }.map(\.title).sorted(),
                       ["in 4 days"], "still snoozed on the 27th")
    }

    func testFourteenDayHorizonIsFast() {
        let now = at("2026-10-26", 9)
        var busy: [(interval: DateInterval, weight: BlockingWeight)] = []
        for i in 0..<200 {
            let d = LocalDay("2026-10-26")!.adding(days: i % 14, calendar: cal).description
            busy.append((DateInterval(start: at(d, 9 + i % 7), end: at(d, 10 + i % 7)), i % 3 == 0 ? .maybe : .blocks))
        }
        let tasks = (0..<50).map { task("t\($0)", due: LocalDay("2026-10-26")!.adding(days: $0 % 14, calendar: cal).description, effort: .m) }
        let start = Date()
        _ = Planning.evaluate(tasks, now: now, sizes: sizes, hours: hours, busy: busy, calendar: cal)
        let ms = Date().timeIntervalSince(start) * 1000
        print("planning 50 tasks × 200 appointments: \(String(format: "%.1f", ms)) ms")
        XCTAssertLessThan(ms, 100)
    }
}
