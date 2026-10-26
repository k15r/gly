# Spec Delta

## Purpose

Brings the appointments of all calendars configured in the macOS system calendar (work Exchange, iCloud, subscribed) into WorkDash, read-only and kept current.

## ADDED Requirements

### Requirement: Read appointments from all system calendars
The system SHALL read appointments from every event calendar configured in the macOS system calendar, including Exchange, iCloud and subscribed calendars. Appointments SHALL be read-only in WorkDash: title, time, location and attendees cannot be changed from WorkDash.

#### Scenario: Work and private appointments appear together
- **WHEN** the system calendar contains an Exchange appointment and an iCloud appointment on the same day
- **THEN** WorkDash lists both for that day, each labeled with its calendar

#### Scenario: Appointment details are not editable
- **WHEN** the user clicks an appointment in the day view
- **THEN** a popover shows its title, time, calendar, location, organizer and attendees, with no editing control

### Requirement: Calendar access permission
The system SHALL request full calendar access on first use and SHALL show a clear state when access is denied or not yet granted, including a way to open the relevant System Settings pane. Without access, the rest of WorkDash (tasks) SHALL remain usable.

#### Scenario: Permission not yet requested
- **WHEN** WorkDash starts for the first time
- **THEN** it asks the system for calendar access

#### Scenario: Permission denied
- **WHEN** calendar access has been denied
- **THEN** the day view shows "No calendar access" with a button that opens the Calendars privacy settings, and the task section still works

### Requirement: Calendar visibility and colors
The system SHALL list all available calendars grouped by account and SHALL let the user show or hide each one. Hidden calendars SHALL not contribute appointments to any view. Each calendar SHALL be displayed with its system color. The visibility choice SHALL persist across app restarts.

#### Scenario: Hiding a calendar
- **WHEN** the user hides the calendar "Birthdays"
- **THEN** no birthday appointments appear in the day view, and they stay hidden after restarting WorkDash

#### Scenario: Newly added calendar
- **WHEN** a calendar is added to the system calendar
- **THEN** it appears in the calendar list and is visible by default

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
- **THEN** WorkDash shows it struck through and labeled "Cancelled"

### Requirement: Calendar refresh indicator
The system SHALL show, per calendar account, when WorkDash last received data or a change from it, so that delays in Exchange synchronization are visible.

#### Scenario: Showing last refresh
- **WHEN** the last change from the Exchange account arrived 25 minutes ago
- **THEN** the day view shows an indicator like "SAP: 25 min ago" for that account

### Requirement: Local time display
The system SHALL display all appointment times in the Mac's current time zone and SHALL handle daylight saving time transitions correctly.

#### Scenario: Day of a DST change
- **WHEN** the displayed day is a daylight saving time transition day
- **THEN** appointments are shown at their correct local times
