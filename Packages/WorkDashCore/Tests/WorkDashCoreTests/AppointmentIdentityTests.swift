import Foundation
import XCTest
@testable import WorkDashCore

final class AppointmentIdentityTests: XCTestCase {
    let occurrence = Date(timeIntervalSinceReferenceDate: 783_000_000)

    func testPlainExternalID() {
        let id = AppointmentIdentity.from(externalID: "SERIES-1", occurrenceDate: occurrence, calendarID: "cal")
        XCTAssertEqual(id.baseID, "SERIES-1")
        XCTAssertEqual(id.originalStart, occurrence)
        XCTAssertEqual(id.occurrenceKey, "cal/SERIES-1@783000000")
        XCTAssertEqual(id.seriesKey, "cal/SERIES-1")
    }

    func testRIDSuffixIsStrippedAndGivesOriginalStart() {
        let moved = occurrence.addingTimeInterval(4 * 3600)    // the occurrence was moved by 4 hours
        let id = AppointmentIdentity.from(externalID: "SERIES-1/RID=783000000", occurrenceDate: moved, calendarID: "cal")
        XCTAssertEqual(id.baseID, "SERIES-1")
        XCTAssertEqual(id.originalStart, occurrence, "original start from the RID, not the moved occurrence date")
    }

    func testKeyIsStableAcrossAMove() {
        let before = AppointmentIdentity.from(externalID: "SERIES-1", occurrenceDate: occurrence, calendarID: "cal")
        let after = AppointmentIdentity.from(externalID: "SERIES-1/RID=783000000", occurrenceDate: occurrence.addingTimeInterval(3600), calendarID: "cal")
        XCTAssertEqual(before.occurrenceKey, after.occurrenceKey)
    }

    func testSameOccurrenceInTwoCalendarsHasTwoKeys() {
        let a = AppointmentIdentity.from(externalID: "X", occurrenceDate: occurrence, calendarID: "work")
        let b = AppointmentIdentity.from(externalID: "X", occurrenceDate: occurrence, calendarID: "shared")
        XCTAssertNotEqual(a.occurrenceKey, b.occurrenceKey)
    }

    func testDefaultsForFakeAppointments() {
        let a = Appointment(id: "1", calendarID: "c", title: "T", start: occurrence, end: occurrence.addingTimeInterval(3600))
        XCTAssertEqual(a.availability, .unknown)
        XCTAssertEqual(a.myStatus, .none)
        XCTAssertEqual(a.identity.baseID, "1")
    }
}
