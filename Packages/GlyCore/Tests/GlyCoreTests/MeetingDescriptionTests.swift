import XCTest
@testable import GlyCore

/// meeting-pages N5 (description, folded dial-in block, join link).
final class MeetingDescriptionTests: XCTestCase {
    func testTeamsBody() {
        let notes = """
        Agenda: scope for Q1
        - roadmap

        ________________________________________________________________________________
        Microsoft Teams meeting
        Join on your computer, mobile app or room device
        Click here to join the meeting<https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=x>
        Meeting ID: 123 456
        ________________________________________________________________________________
        """
        let d = MeetingDescription.parse(notes: notes, location: "Microsoft Teams Meeting", url: nil)
        XCTAssertEqual(d.agenda, "Agenda: scope for Q1\n- roadmap")
        XCTAssertEqual(d.service, "Teams")
        XCTAssertEqual(d.joinURL?.host, "teams.microsoft.com")
        XCTAssertTrue(d.dialIn?.hasPrefix("Microsoft Teams meeting") ?? false)
        XCTAssertFalse(d.dialIn?.contains("____") ?? true)
    }

    func testZoomInLocation() {
        let d = MeetingDescription.parse(notes: "Bring numbers", location: "https://example.zoom.us/j/987654?pwd=x", url: nil)
        XCTAssertEqual(d.service, "Zoom")
        XCTAssertEqual(d.joinURL?.absoluteString, "https://example.zoom.us/j/987654?pwd=x")
        XCTAssertEqual(d.agenda, "Bring numbers")
        XCTAssertNil(d.dialIn)
    }

    func testPlainAndEmpty() {
        let plain = MeetingDescription.parse(notes: "Just talk", location: "Room 2", url: nil)
        XCTAssertEqual(plain.agenda, "Just talk")
        XCTAssertNil(plain.joinURL)
        let none = MeetingDescription.parse(notes: nil, location: nil, url: nil)
        XCTAssertEqual(none, MeetingDescription(agenda: "", dialIn: nil, joinURL: nil, service: nil))
    }
}
