import XCTest
@testable import GlyCore

final class DayModelTests: XCTestCase {
    var berlin: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }()
    let calendars = [CalendarInfo(id: "sap", title: "Kalender", sourceID: "ex", sourceTitle: "Exchange", colorHex: "#1E88E5"),
                     CalendarInfo(id: "home", title: "Family", sourceID: "ic", sourceTitle: "iCloud", colorHex: "#43A047"),
                     CalendarInfo(id: "hol", title: "Holidays", sourceID: "sub", sourceTitle: "Subscribed", colorHex: "#E53935")]
    let day = LocalDay("2026-10-27")!

    func at(_ hhmm: String, _ dayString: String = "2026-10-27") -> Date { Due(day: dayString, time: hhmm).date(in: berlin)! }
    func appt(_ id: String, _ cal: String, _ from: Date, _ to: Date, allDay: Bool = false, cancelled: Bool = false) -> Appointment {
        Appointment(id: id, calendarID: cal, title: id, start: from, end: to, isAllDay: allDay, isCancelled: cancelled)
    }
    func model(now: Date, _ appts: [Appointment], tasks: [DayTask] = [], day: LocalDay? = nil) -> DayModel {
        DayModel(day: day ?? self.day, now: now, calendar: berlin, appointments: appts, calendars: calendars, tasks: tasks)
    }

    func testAppointmentsFromSeveralCalendarsInStartOrderWithCalendarInfo() {
        let m = model(now: at("08:00"), [appt("dinner", "home", at("18:00"), at("20:00")),
                                         appt("review", "sap", at("13:00"), at("14:00")),
                                         appt("1:1", "sap", at("09:00"), at("09:30"))])
        XCTAssertEqual(m.timed.map(\.appointment.title), ["1:1", "review", "dinner"])
        XCTAssertEqual(m.timed.map { $0.calendar?.title }, ["Kalender", "Kalender", "Family"])
        XCTAssertEqual(m.timed.last?.calendar?.colorHex, "#43A047")
    }

    func testOverlappingAppointmentsAreAllKept() {
        let m = model(now: at("08:00"), [appt("a", "sap", at("10:00"), at("11:00")), appt("b", "home", at("10:30"), at("11:30"))])
        XCTAssertEqual(m.timed.count, 2)
    }

    func testAppointmentSpanningMidnightAppearsOnBothDays() {
        let late = appt("late", "home", at("22:00", "2026-10-26"), at("01:00"))
        let prev = model(now: at("08:00"), [late], day: LocalDay("2026-10-26")!)
        let cur = model(now: at("08:00"), [late])
        XCTAssertEqual(prev.timed.map(\.appointment.title), ["late"])
        XCTAssertTrue(prev.timed[0].endsAfterDay)
        XCTAssertEqual(cur.timed.map(\.appointment.title), ["late"])
        XCTAssertTrue(cur.timed[0].startsBeforeDay)
    }

    func testAllDayAppointmentsAreSeparate() {
        let m = model(now: at("08:00"), [appt("Holiday", "hol", berlin.startOfDay(for: at("12:00")), at("00:00", "2026-10-28"), allDay: true),
                                         appt("meeting", "sap", at("09:00"), at("10:00"))])
        XCTAssertEqual(m.allDay.map(\.appointment.title), ["Holiday"])
        XCTAssertEqual(m.timed.map(\.appointment.title), ["meeting"])
        XCTAssertEqual(m.allDay[0].state, .notToday, "all-day entries have no past/current styling")
    }

    func testPastCurrentUpcomingDuringAMeeting() {
        let m = model(now: at("09:15"), [appt("early", "sap", at("08:00"), at("08:30")),
                                         appt("now", "sap", at("09:00"), at("09:30")),
                                         appt("later", "sap", at("13:00"), at("14:00"))])
        XCTAssertTrue(m.isToday)
        XCTAssertEqual(m.timed.map(\.state), [.past, .current, .upcoming])
    }

    func testOtherDaysHaveNoTimeState() {
        let m = model(now: at("09:15", "2026-10-26"), [appt("x", "sap", at("09:00"), at("09:30"))])
        XCTAssertFalse(m.isToday)
        XCTAssertEqual(m.timed.map(\.state), [.notToday])
    }

    func testDSTDayShowsCorrectLocalTimes() {
        // 2026-10-25 (25 h): an appointment at 09:00 local must be within the day and keep 09:00.
        let dst = LocalDay("2026-10-25")!
        let nine = Due(day: "2026-10-25", time: "09:00").date(in: berlin)!
        let lateEvening = Due(day: "2026-10-25", time: "23:30").date(in: berlin)!
        let m = model(now: nine, [appt("morning", "sap", nine, nine + 1800), appt("late", "home", lateEvening, lateEvening + 1200)], day: dst)
        XCTAssertEqual(m.timed.map(\.appointment.title), ["morning", "late"])
        XCTAssertEqual(berlin.component(.hour, from: m.timed[0].appointment.start), 9)
        XCTAssertFalse(m.timed[1].endsAfterDay, "23:30-23:50 stays within the 25-hour day")
    }

    func testCancelledFlagIsPassedThroughAndEmptyState() {
        let m = model(now: at("08:00"), [appt("sync", "sap", at("10:00"), at("10:30"), cancelled: true)])
        XCTAssertTrue(m.timed[0].appointment.isCancelled)
        XCTAssertFalse(model(now: at("08:00"), []).hasAppointments)
    }

    func testOutOfDayAppointmentsFromSourceAreDropped() {
        let m = model(now: at("08:00"), [appt("tomorrow", "sap", at("09:00", "2026-10-28"), at("10:00", "2026-10-28"))])
        XCTAssertFalse(m.hasAppointments)
    }
}
