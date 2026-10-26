import Foundation
import XCTest
@testable import WorkDashCore

final class BlockingTests: XCTestCase {
    func appt(allDay: Bool = false, cancelled: Bool = false, availability: Availability = .busy, status: ParticipationStatus = .accepted) -> Appointment {
        let start = Date(timeIntervalSinceReferenceDate: 783_000_000)
        return Appointment(id: "1", calendarID: "c", title: "T", start: start, end: start.addingTimeInterval(3600), isAllDay: allDay,
                           isCancelled: cancelled, availability: availability, myStatus: status)
    }

    func testAutomaticRules() {
        let cases: [(String, Appointment, BlockingWeight)] = [
            ("accepted busy", appt(), .blocks),
            ("declined meeting", appt(status: .declined), .free),
            ("cancelled", appt(cancelled: true), .free),
            ("availability free", appt(availability: .free), .free),
            ("tentative meeting", appt(status: .tentative), .maybe),
            ("unanswered meeting", appt(status: .pending), .maybe),
            ("availability tentative", appt(availability: .tentative, status: .none), .maybe),
            ("no attendees, unknown availability", appt(availability: .unknown, status: .none), .blocks),
            ("out of office all day", appt(allDay: true, availability: .unavailable, status: .none), .blocks),
            ("busy all day", appt(allDay: true, availability: .busy, status: .none), .blocks),
            ("holiday all day (free)", appt(allDay: true, availability: .free, status: .none), .free),
            ("all day unknown", appt(allDay: true, availability: .unknown, status: .none), .free),
            ("declined beats tentative availability", appt(availability: .tentative, status: .declined), .free),
        ]
        for (name, a, expected) in cases {
            XCTAssertEqual(Blocking.classify(a).weight, expected, name)
            XCTAssertEqual(Blocking.classify(a).reason, .automatic, name)
        }
    }

    func testOverrides() {
        XCTAssertEqual(Blocking.classify(appt(), occurrence: .ignore).weight, .free)
        XCTAssertEqual(Blocking.classify(appt(status: .declined), occurrence: .blocks).weight, .blocks)
        XCTAssertEqual(Blocking.classify(appt(), series: .optional).weight, .maybe)
        XCTAssertEqual(Blocking.classify(appt(), series: .optional).reason, .seriesOverride)
    }

    func testExceptionInAnOptionalSeries() {
        let r = Blocking.classify(appt(), occurrence: .blocks, series: .optional)
        XCTAssertEqual(r.weight, .blocks)
        XCTAssertEqual(r.reason, .occurrenceOverride)
    }
}
