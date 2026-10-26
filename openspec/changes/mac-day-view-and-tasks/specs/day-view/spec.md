# Spec Delta

## Purpose

The main screen of WorkDash: one day at a glance, with all visible appointments and the tasks that matter that day, so it can serve as the single source for the day.

## ADDED Requirements

### Requirement: Day view shows today on launch
The system SHALL open on a day view of the current local date. The view SHALL show the weekday and date.

#### Scenario: Launch
- **WHEN** the user opens WorkDash on Monday, 27 October 2026
- **THEN** the day view shows "Mon 27 Oct 2026" with that day's appointments and tasks

### Requirement: Merged appointment timeline
The day view SHALL show all appointments of visible calendars that overlap the displayed day in one list ordered by start time. Each entry SHALL show the start and end time, title, calendar color and calendar name. Overlapping appointments SHALL all be shown.

#### Scenario: Appointments from several calendars
- **WHEN** the day has a 09:00 SAP meeting, a 13:00 SAP meeting and an 18:00 iCloud appointment
- **THEN** they appear in that order, each with its calendar's color and name

#### Scenario: Overlapping appointments
- **WHEN** two appointments overlap in time
- **THEN** both are listed, and neither is hidden

#### Scenario: Appointment spanning midnight
- **WHEN** an appointment runs from 22:00 the previous day to 01:00
- **THEN** it appears on both days

### Requirement: All-day appointments
The day view SHALL show all-day appointments separately above the timed appointments.

#### Scenario: Holiday
- **WHEN** the day is a public holiday from a subscribed holiday calendar
- **THEN** the holiday appears in the all-day section

### Requirement: Current and past appointments
On the current day, the day view SHALL visually distinguish appointments that are over, the appointment currently running, and upcoming ones. This SHALL update as time passes without user action.

#### Scenario: During a meeting
- **WHEN** the time is 09:15 and a meeting runs from 09:00 to 09:30
- **THEN** that meeting is highlighted as current, and earlier meetings appear dimmed

### Requirement: Day navigation
The system SHALL let the user move to the previous day, the next day and back to today, by buttons and by keyboard shortcuts.

#### Scenario: Next day
- **WHEN** the user presses the next-day shortcut
- **THEN** the view shows the following day's appointments and tasks

#### Scenario: Back to today
- **WHEN** the user is viewing another day and chooses "Today"
- **THEN** the view returns to the current date

### Requirement: Tasks for the day
The day view SHALL show the open tasks due on the displayed day. When the displayed day is today, it SHALL also show overdue open tasks, marked as overdue. A snoozed task SHALL appear on its snooze day regardless of its due date, marked "back from snooze", and not before. Tasks SHALL be sorted by priority (urgent first), then by due time.

#### Scenario: Due and overdue tasks today
- **WHEN** today has an urgent task due today, a normal task due today, and a normal task due yesterday that is still open
- **THEN** the day view lists the urgent task first, then the overdue normal task marked "overdue" (earlier due time), then the normal task due today

#### Scenario: Future day
- **WHEN** the user views tomorrow
- **THEN** only tasks due tomorrow appear, and no overdue tasks

#### Scenario: Snoozed until tomorrow
- **WHEN** a task due today is snoozed until tomorrow and the user views tomorrow
- **THEN** the task appears there marked "back from snooze", and it no longer appears today

### Requirement: Act on tasks from the day view
The system SHALL let the user complete a task, open it for editing, and create a new task due on the displayed day directly from the day view.

#### Scenario: Complete from the day view
- **WHEN** the user ticks a task in the day view
- **THEN** the task is marked done and leaves the list

#### Scenario: New task for the displayed day
- **WHEN** the user creates a task from the day view while viewing tomorrow
- **THEN** the new task's due date is tomorrow

### Requirement: Empty and unavailable states
The day view SHALL show an explicit message when the day has no appointments or no tasks, and when calendar access is missing, instead of an empty area.

#### Scenario: Free day
- **WHEN** the displayed day has no appointments
- **THEN** the appointment section says "No appointments"
