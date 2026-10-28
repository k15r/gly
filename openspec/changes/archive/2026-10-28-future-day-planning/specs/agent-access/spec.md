# Spec Delta

## MODIFIED Requirements

### Requirement: Read the schedule of a day
The system SHALL provide an MCP tool `get_schedule` that returns, for a given date (default: today, local time), the appointments of all visible calendars and the tasks the day view shows for that date: for today and later dates the open tasks due that day and those overdue as seen from that date; for past dates the open tasks due that day.

#### Scenario: Today's schedule
- **WHEN** an agent calls `get_schedule` without arguments
- **THEN** it receives today's appointments in start order and today's due and overdue open tasks, matching the day view

#### Scenario: Another day
- **WHEN** a task due today is still open and an agent calls `get_schedule` with tomorrow's date
- **THEN** it receives tomorrow's appointments, the tasks due tomorrow, and the task due today flagged as overdue, matching tomorrow's day view

#### Scenario: Past day
- **WHEN** an agent calls `get_schedule` with yesterday's date
- **THEN** it receives yesterday's appointments and the open tasks due yesterday, without overdue tasks and without planning data

#### Scenario: No calendar access
- **WHEN** the agent process has no calendar access
- **THEN** `get_schedule` still returns the tasks, and reports that appointments are unavailable because calendar access is missing

### Requirement: Planning data in the schedule
The `get_schedule` response SHALL include the day's free time and, for today and later dates, the Today list of that day (with why each task is there, the work needed that day and whether it can't fit) and its Coming up list (with each task's start-by day), computed as in the day view: for today from now on, for a later date from the start of that day.

#### Scenario: Planning data
- **WHEN** an agent calls `get_schedule` for today
- **THEN** it receives the free time left today, the Today tasks with reason, effort, work needed today and can't-fit flag, and the Coming up tasks with start-by day

#### Scenario: Planning data for a later day
- **WHEN** an agent calls `get_schedule` for Wednesday while it is Monday
- **THEN** it receives Wednesday's whole free working time, Wednesday's Today tasks with the work needed that day, and the Coming up tasks for the days after Wednesday
