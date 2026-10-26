# Spec Delta

## MODIFIED Requirements

### Requirement: Read the schedule of a day
The system SHALL provide an MCP tool `get_schedule` that returns, for a given date (default: today, local time), the appointments of all visible calendars and the tasks the day view shows for that date. Each appointment SHALL include title, start, end, all-day flag, cancelled flag, calendar name, location, organizer, attendees, and how it counts for free time (blocks, maybe, free) with the reason (automatic or override). The response SHALL include the day's free time and, for today, the Today list (with why each task is there, the work needed today and whether it can't fit) and the Coming up list (with each task's start-by day).

#### Scenario: Today's schedule
- **WHEN** an agent calls `get_schedule` without arguments
- **THEN** it receives today's appointments in start order and today's due and overdue open tasks, matching the day view

#### Scenario: Another day
- **WHEN** an agent calls `get_schedule` with `date: "2026-10-28"`
- **THEN** it receives the appointments and tasks due on 28 October, without overdue tasks

#### Scenario: No calendar access
- **WHEN** the agent process has no calendar access
- **THEN** `get_schedule` still returns the tasks, and reports that appointments are unavailable because calendar access is missing

#### Scenario: Planning data
- **WHEN** an agent calls `get_schedule` for today
- **THEN** it receives the free time left today, the Today tasks with reason, effort, work needed today and can't-fit flag, and the Coming up tasks with start-by day

## ADDED Requirements

### Requirement: Effort over MCP
Task results SHALL include the effort (or null), and `create_task` and `update_task` SHALL accept an optional effort (`XS`, `S`, `M`, `L`, `XL`; null on update removes it).

#### Scenario: Agent estimates a task
- **WHEN** an agent creates a task with `effort: "M"`
- **THEN** the task has effort `M` and is planned in the day view's Today or Coming up list if it is due within the horizon
