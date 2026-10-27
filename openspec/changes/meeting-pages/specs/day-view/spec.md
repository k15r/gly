# Spec Delta

## ADDED Requirements

### Requirement: Appointment details
Clicking an appointment SHALL show its details at the click position: title, time, calendar, location, organizer, attendees and the description (links clickable, dial-in block folded), with a Join button when a meeting link is present, and "Notes", which opens the meeting page. The attendee list SHALL be folded to its count. A click outside SHALL close the details.

#### Scenario: Description and join link
- **WHEN** the user clicks a Teams meeting whose description contains an agenda and the Teams block
- **THEN** the details show the agenda, the Teams details folded, the attendees folded to "N attendees", a Join button and "Notes"

### Requirement: Meetings with notes are marked
Appointments that have notes (their own, or their series') SHALL show a small note icon in the day view.

#### Scenario: Series notes marked
- **WHEN** the series of "1:1 Alex" has notes
- **THEN** every occurrence of it shows the note icon, also on days without its own section
