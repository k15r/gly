import Foundation
import GRDB
import XCTest
@testable import GlyCore

/// specs/daily-planning "Today list", "Work needed today", "Today's load", "Coming up".
final class PlanningTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }()
    let hours = WorkingHours()
    var sizes: EffortSizes { .defaults(for: hours) }
    func at(_ d: String, _ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: LocalDay(d)!.interval(in: cal).start)! }
    func task(_ title: String, due: String, time: String? = nil, effort: Effort?, priority: Priority = .none) -> TaskItem {
        TaskItem(id: title, title: title, body: "", status: .open, priority: priority, due: Due(day: due, time: time), snoozedUntil: nil,
                 tags: [], createdAt: Date(), modifiedAt: Date(), modifiedBy: "u", completedAt: nil, effort: effort)
    }
    func blocked(_ day: String) -> (interval: DateInterval, weight: BlockingWeight) {
        (DateInterval(start: at(day, 0), end: at(day, 23, 59)), .blocks)
    }
    func plan(_ tasks: [TaskItem], now: Date, busy: [(interval: DateInterval, weight: BlockingWeight)] = []) -> DayPlan {
        Planning.plan(tasks, now: now, sizes: sizes, hours: hours, busy: busy, calendar: cal)
    }

    func testDefaultSizes() {
        XCTAssertEqual(sizes[.l], 480)
        XCTAssertEqual(sizes[.xl], 1440)
        XCTAssertEqual(EffortSizes.defaults(for: WorkingHours(startMinute: 8 * 60, endMinute: 14 * 60))[.l], 360)
    }

    func testTaskNeedingWorkToday() {
        // Monday 09:00; XL (3 working days) due Friday, but Thursday is fully booked → 2 free days after today (Tue, Wed) + Fri.
        // Free after today until Fri evening: Tue, Wed, Fri = 3 days → nothing needed. Make Wednesday booked too: 2 days → needs 1 day today.
        let p = plan([task("big", due: "2026-10-30", effort: .xl)], now: at("2026-10-26", 9),
                     busy: [blocked("2026-10-28"), blocked("2026-10-29")])
        XCTAssertEqual(p.today.map(\.task.title), ["big"])
        XCTAssertEqual(p.today.first?.reason, .needsWork)
        XCTAssertEqual(p.today.first?.neededToday, 480)
        XCTAssertEqual(p.today.first?.cantFit, false)
    }

    func testEnoughTimeLaterIsComingUp() {
        let p = plan([task("small", due: "2026-10-30", effort: .s)], now: at("2026-10-26", 9))
        XCTAssertEqual(p.today, [])
        XCTAssertEqual(p.comingUp.map(\.task.title), ["small"])
    }

    func testDueTodayWithoutEstimate() {
        let p = plan([task("x", due: "2026-10-26", effort: nil)], now: at("2026-10-26", 9))
        XCTAssertEqual(p.today.first?.reason, .dueToday)
        XCTAssertNil(p.today.first?.neededToday)
        XCTAssertEqual(p.withoutEstimate, 1)
    }

    func testCantFitComesFirst() {
        let p = plan([task("normal due today", due: "2026-10-26", effort: .s, priority: .urgent),
                      task("too big", due: "2026-10-26", time: "17:00", effort: .m)], now: at("2026-10-26", 15))
        XCTAssertEqual(p.today.map(\.task.title), ["too big", "normal due today"])
        XCTAssertEqual(p.today.first?.cantFit, true)
    }

    func testOrderingOverdueDueTodayNeedsWork() {
        let p = plan([task("needs", due: "2026-10-28", effort: .xl),   // 24 h, 16 h free after today → 8 h today, fits exactly
                      task("due today", due: "2026-10-26", effort: .xs),
                      task("overdue", due: "2026-10-23", effort: nil)], now: at("2026-10-26", 9))
        XCTAssertEqual(p.today.map(\.task.title), ["overdue", "due today", "needs"])
    }

    func testOverbookedLoad() {
        let p = plan([task("a", due: "2026-10-26", effort: .m), task("b", due: "2026-10-26", effort: .m), task("c", due: "2026-10-26", effort: nil)],
                     now: at("2026-10-26", 9))
        XCTAssertEqual(p.neededMinutes, 480)
        XCTAssertEqual(p.withoutEstimate, 1)
    }

    func testStartBy() {
        // L (1 day) due Thursday; Wednesday free, Thursday booked → start by Wednesday.
        let p = plan([task("t", due: "2026-10-29", effort: .l)], now: at("2026-10-26", 9), busy: [blocked("2026-10-29")])
        XCTAssertEqual(p.comingUp.first?.startBy, LocalDay("2026-10-28"))
        // Without estimate: last, no start-by.
        let q = plan([task("none", due: "2026-10-27", effort: nil), task("t", due: "2026-10-30", effort: .s)], now: at("2026-10-26", 9))
        XCTAssertEqual(q.comingUp.map(\.task.title), ["t", "none"])
        XCTAssertNil(q.comingUp.last?.startBy)
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
        _ = plan(tasks, now: now, busy: busy)
        let ms = Date().timeIntervalSince(start) * 1000
        print("planning 50 tasks × 200 appointments: \(String(format: "%.1f", ms)) ms")
        XCTAssertLessThan(ms, 200)
    }
}
