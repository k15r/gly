import XCTest
@testable import GlyCore

/// subtasks S1, S2: specs/tasks "Parts of a task", specs/daily-planning "Remaining effort from parts".
final class ChecklistPartsTests: XCTestCase {
    let sizes = EffortSizes.defaults(for: WorkingHours())     // S = 120, L = 480; a working day = 480

    func task(_ notes: String, effort: Effort? = nil, worked: Int = 0) -> TaskItem {
        var t = TaskItem(id: "t", title: "Report", body: notes, status: .open, priority: .none, due: nil, snoozedUntil: nil,
                         tags: [], createdAt: Date(), modifiedAt: Date(), modifiedBy: "u", completedAt: nil, effort: effort)
        t.workedMinutes = worked
        return t
    }

    func testBreakATaskDown() {
        let parts = ChecklistParts.parse("Intro text\n- [ ] Outline (S)\n- [ ] Draft (1d)\n* [ ] Review (90m)\n")
        XCTAssertEqual(parts.map(\.title), ["Outline", "Draft", "Review"])
        XCTAssertEqual(parts.map { $0.estimate?.minutes(sizes: sizes, dayMinutes: 480) }, [120, 480, 90])
        XCTAssertEqual(parts.filter(\.done).count, 0)
    }

    func testItemWithoutEstimateAndDoneMarks() {
        let parts = ChecklistParts.parse("- [x] Book room\n  - [X] Nested (2h)\n- [ ] Call (maybe)")
        XCTAssertEqual(parts, [TaskPart(title: "Book room", done: true),
                               TaskPart(title: "Nested", estimate: .duration(days: 0, minutes: 120), done: true),
                               TaskPart(title: "Call (maybe)")])
    }

    func testEstimateForms() {
        func estimate(_ s: String) -> PartEstimate? { ChecklistParts.parse("- [ ] X \(s)").first?.estimate }
        XCTAssertEqual(estimate("(XL)"), .size(.xl))
        XCTAssertEqual(estimate("(1d 4h)"), .duration(days: 1, minutes: 240))
        XCTAssertEqual(estimate("(1h30m)"), .duration(days: 0, minutes: 90))
        XCTAssertEqual(estimate("(30m)"), .duration(days: 0, minutes: 30))
        XCTAssertNil(estimate("(s)"), "sizes are upper case")
        XCTAssertNil(estimate("()"))
        XCTAssertNil(estimate("(2h) later"), "only at the end")
        XCTAssertEqual(ChecklistParts.parse("- [ ] (2h)").count, 0, "an estimate alone is no part")
    }

    func testCodeBlocksAndOtherLinesAreIgnored() {
        let notes = "```\n- [ ] not a part\n```\n- not a checkbox\n-[ ] no space\n- [ ] real"
        XCTAssertEqual(ChecklistParts.parse(notes).map(\.title), ["real"])
    }

    func testTickingOffAPart() {
        // "Ticking off a part": Outline S, Draft L, Review 2h → tick Outline → 1 day 2 hours.
        let open = task("- [ ] Outline (S)\n- [ ] Draft (L)\n- [ ] Review (2h)", effort: .xl)
        XCTAssertEqual(open.remaining(sizes: sizes, dayMinutes: 480), 120 + 480 + 120)
        let ticked = task("- [x] Outline (S)\n- [ ] Draft (L)\n- [ ] Review (2h)", effort: .xl)
        XCTAssertEqual(ticked.remaining(sizes: sizes, dayMinutes: 480), 480 + 120)
        XCTAssertTrue(ticked.hasEstimatedParts)
    }

    func testUnestimatedParts() {
        // "Unestimated parts": the task's own effort and recorded work stay in charge.
        let t = task("- [ ] One\n- [ ] Two", effort: .l, worked: 60)
        XCTAssertFalse(t.hasEstimatedParts)
        XCTAssertEqual(t.remaining(sizes: sizes, dayMinutes: 480), 420)
    }

    func testDaysFollowTheWorkingDay() {
        let t = task("- [ ] Draft (1d)")
        XCTAssertEqual(t.remaining(sizes: sizes, dayMinutes: 360), 360)
        XCTAssertEqual(t.remaining(sizes: sizes, dayMinutes: 480), 480)
    }

    func testEstimatedPartsWithoutTaskEffort() {
        XCTAssertEqual(task("- [ ] A (S)\n- [ ] B").remaining(sizes: sizes, dayMinutes: 480), 120, "unestimated items count as zero")
    }
}
