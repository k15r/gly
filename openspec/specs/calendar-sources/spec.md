# calendar-sources Specification

## Purpose

Brings the appointments of all calendars configured in the macOS system calendar (work Exchange, iCloud, subscribed) into gly, read-only and kept current.

## Requirements

### Requirement: Read appointments from all system calendars
The system SHALL read appointments from every event calendar configured in the macOS system calendar, including Exchange, iCloud and subscribed calendars. Appointments SHALL be read-only in gly: title, time, location and attendees cannot be changed from gly.

#### Scenario: Work and private appointments appear together
- **WHEN** the system calendar contains an Exchange appointment and an iCloud appointment on the same day
- **THEN** gly lists both for that day, each labeled with its calendar

#### Scenario: Appointment details are not editable
- **WHEN** the user clicks an appointment in the day view
- **THEN** a popover shows its title, time, calendar, location, organizer and attendees, with no editing control

### Requirement: Calendar access permission
The system SHALL request full calendar access on first use and SHALL show a clear state when access is denied or not yet granted, including a way to open the relevant System Settings pane. Without access, the rest of gly (tasks) SHALL remain usable.

#### Scenario: Permission not yet requested
- **WHEN** gly starts for the first time
- **THEN** it asks the system for calendar access

#### Scenario: Permission denied
- **WHEN** calendar access has been denied
- **THEN** the day view shows "No calendar access" with a button that opens the Calendars privacy settings, and the task section still works

### Requirement: Calendar visibility and colors
The system SHALL list all available calendars grouped by account and SHALL let the user show or hide each one. Hidden calendars SHALL not contribute appointments to any view, nor to the schedule agents read over MCP. Each calendar SHALL be displayed with its system color. The visibility choice SHALL persist across app restarts.

#### Scenario: Hiding a calendar
- **WHEN** the user hides the calendar "Birthdays"
- **THEN** no birthday appointments appear in the day view, and they stay hidden after restarting gly

#### Scenario: Newly added calendar
- **WHEN** a calendar is added to the system calendar
- **THEN** it appears in the calendar list and is visible by default

#### Scenario: Hidden calendar and agents
- **WHEN** the user hides the calendar "Birthdays" and an agent reads today's schedule over MCP
- **THEN** the schedule contains no birthday appointments

### Requirement: Live updates from the system calendar
The system SHALL reflect changes in the system calendar (new, moved, renamed, cancelled or deleted appointments) without a manual refresh, within a few seconds of the system calendar having the change.

#### Scenario: Appointment moved in Outlook
- **WHEN** an appointment's new time arrives in the system calendar
- **THEN** the day view shows it at the new time without user action

#### Scenario: Appointment deleted
- **WHEN** an appointment disappears from the system calendar
- **THEN** it disappears from the day view

### Requirement: Cancelled appointments stay visible
The system SHALL show appointments that the system calendar reports as cancelled, marked as cancelled (struck through or equivalent). Appointments whose title starts with "Canceled:" SHALL be treated as cancelled as well.

#### Scenario: Organizer cancels a meeting
- **WHEN** an Exchange meeting is cancelled by its organizer and stays in the system calendar with status cancelled
- **THEN** gly shows it struck through and labeled "Cancelled"

### Requirement: Calendar refresh indicator
The system SHALL show, per calendar account, when gly last received data or a change from it, so that delays in Exchange synchronization are visible. The information SHALL be available on demand (in the tooltip of the day view's refresh button) rather than taking space in the day view header.

#### Scenario: Showing last refresh
- **WHEN** the last change from the Exchange account arrived 25 minutes ago and the user hovers over the refresh button
- **THEN** the tooltip lists "Exchange: 25 min ago" for that account

### Requirement: Local time display
The system SHALL display all appointment times in the Mac's current time zone and SHALL handle daylight saving time transitions correctly.

#### Scenario: Day of a DST change
- **WHEN** the displayed day is a daylight saving time transition day
- **THEN** appointments are shown at their correct local times
