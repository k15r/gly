import XCTest
@testable import GlyCore

/// status-colors C2: specs/appearance "Status colors", "Task rows".
final class RowStatusTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }()
    let today = LocalDay("2026-10-29")!     // Thursday

    func task(due: String?, status: TaskStatus = .open, snoozedUntil: String? = nil) -> TaskItem {
        TaskItem(id: "t", title: "Report", body: "", status: status, priority: .none, due: due.map { Due(day: $0) }, snoozedUntil: snoozedUntil,
                 tags: [], createdAt: Date(), modifiedAt: Date(), modifiedBy: "u", completedAt: nil, effort: .m)
    }
    func item(_ t: TaskItem, _ reason: TodayReason, needed: Int?, cantFit: Bool = false) -> TodayItem {
        TodayItem(task: t, reason: reason, effortMinutes: 240, neededToday: needed, cantFit: cantFit)
    }
    func status(_ t: TaskItem, day: LocalDay? = nil, plan: TodayItem? = nil) -> RowStatus? {
        RowStatus.of(t, day: day ?? today, today: today, plan: plan, dayLength: 480, calendar: cal)
    }

    func testOverdueTaskRow() {
        // "Overdue task row": due yesterday → red, "overdue since yesterday".
        let s = status(task(due: "2026-10-28"))
        XCTAssertEqual(s?.kind, .overdue)
        XCTAssertEqual(s?.tooltip, "Overdue since yesterday")
    }

    func testOrderCantFitBeatsOverdue() {
        let t = task(due: "2026-10-28")
        XCTAssertEqual(status(t, plan: item(t, .overdue, needed: 240, cantFit: true))?.kind, .cantFit)
    }

    func testDueTodayAndNeedsWork() {
        XCTAssertEqual(status(task(due: "2026-10-29"))?.tooltip, "Due today")
        let later = task(due: "2026-10-30")
        let s = status(later, plan: item(later, .needsWork, needed: 120))
        XCTAssertEqual(s?.kind, .needsWork)
        XCTAssertEqual(s?.tooltip, "At least 2h today to finish by tomorrow")
    }

    func testForecastDaySpeaksFromThatDay() {
        let t = task(due: "2026-10-30")
        XCTAssertEqual(status(t, day: LocalDay("2026-10-30")!)?.kind, .dueToday, "on Friday's view")
        XCTAssertEqual(status(t, day: LocalDay("2026-11-02")!)?.kind, .overdue, "on Monday's view")
    }

    func testBackFromSnoozeIsWeakest() {
        var t = task(due: "2026-11-03", snoozedUntil: nil)
        t.snoozeEndedOn = "2026-10-29"
        let s = status(t)
        XCTAssertEqual(s?.kind, .backFromSnooze)
        XCTAssertTrue(s?.tooltip.hasPrefix("Back from snooze (was until today) – due ") == true, s?.tooltip ?? "")
        var due = task(due: "2026-10-29"); due.snoozeEndedOn = "2026-10-29"
        XCTAssertEqual(status(due)?.kind, .dueToday, "due today wins")
    }

    func testDoneDroppedAndPlain() {
        XCTAssertEqual(status(task(due: "2026-10-20", status: .done))?.kind, .done)
        XCTAssertNil(status(task(due: "2026-10-20", status: .dropped)))
        XCTAssertNil(status(task(due: "2026-11-10")))
        XCTAssertNil(status(task(due: nil)))
    }

    func testDurations() {
        XCTAssertEqual(Durations.effort(90, dayLength: 480), "1h 30m")
        XCTAssertEqual(Durations.effort(600, dayLength: 480), "1d 2h")
        XCTAssertEqual(Durations.clock(45), "45m")
    }
}
