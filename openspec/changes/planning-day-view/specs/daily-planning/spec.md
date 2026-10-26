# Spec Delta

## Purpose

Shows each day what to work on so that tasks are done by their due dates, based on how much work each task is and how much free time the calendar really leaves.

## ADDED Requirements

### Requirement: Effort sizes
A task MAY have an effort of `XS`, `S`, `M`, `L` or `XL`. Each size SHALL stand for an amount of working time that the user can configure in Settings; the defaults SHALL be 30 minutes, 2 hours, 4 hours, 1 working day and 3 working days, where a working day is the length of the working hours.

#### Scenario: Default sizes
- **WHEN** the working hours are 09:00–17:00 and nothing was configured
- **THEN** `L` stands for 8 hours and `XL` for 24 hours of working time

#### Scenario: Configured size
- **WHEN** the user sets `M` to 3 hours in Settings
- **THEN** every task with effort `M` counts as 3 hours of work

### Requirement: Working hours
The system SHALL use one configurable daily working-hours window, the same for every day (default 09:00–17:00). Free time SHALL only be counted inside this window.

#### Scenario: Change working hours
- **WHEN** the user sets working hours to 08:00–16:00
- **THEN** free time for every day is counted between 08:00 and 16:00

### Requirement: How appointments block time
Each appointment SHALL count as blocking (fully), maybe (half) or free (not at all). Without an override, the system SHALL classify it from the calendar: cancelled or declined appointments and appointments marked "free" are free; all-day appointments are free unless they are marked out of office or busy, which block the whole day; tentative or unanswered appointments are maybe; all others block. A blocking override from the user SHALL take precedence.

#### Scenario: Declined meeting
- **WHEN** the user declined a 10:00–11:00 meeting
- **THEN** that hour counts as free time

#### Scenario: Tentative meeting
- **WHEN** an unanswered meeting runs 13:00–14:00
- **THEN** it reduces the free time by 30 minutes

#### Scenario: Out of office
- **WHEN** an all-day appointment on Friday is marked out of office
- **THEN** Friday has no free time

### Requirement: Free time
The free time of a day SHALL be the working hours minus the time covered by blocking appointments, minus half the time covered only by maybe appointments, counting overlapping appointments once. For today, only the working time from now on SHALL count.

#### Scenario: Overlapping meetings
- **WHEN** two blocking meetings overlap from 10:00 to 11:30 (10:00–11:00 and 10:30–11:30)
- **THEN** 1.5 hours are subtracted, not 2

#### Scenario: Later today
- **WHEN** it is 15:00 on a day with working hours until 17:00 and no more meetings
- **THEN** today's free time is 2 hours

### Requirement: Work on list
On today's day view, besides the tasks due today and overdue, the system SHALL list the open tasks due within the next N days (N configurable, default 5, switchable in the day view header). Snoozed tasks SHALL not appear before their snooze date. The list SHALL be sorted by urgency: late, tight, start today, ok, then tasks without an estimate; within a state by due date.

#### Scenario: Horizon
- **WHEN** the horizon is 5 days and a task is due in 4 days and another in 8 days
- **THEN** only the first appears under "Work on"

#### Scenario: Switch the horizon
- **WHEN** the user switches the horizon in the day view header to 14 days
- **THEN** the list includes tasks due in the next 14 days, and the choice is kept

### Requirement: Work on states
For each task in the list with an effort, the system SHALL compare its effort with the free time from now until its due date (the end of the due day, or the due time), and show: late when the free time is less than the effort; tight when it is less than 1.5 times the effort; start today when it is less than twice the effort or the task is due tomorrow; ok otherwise. Tasks are compared one by one, without sharing free time between them. A task without effort SHALL be marked "no estimate".

#### Scenario: Tight task
- **WHEN** a task with effort `L` (8 h) is due Wednesday and the free time until Wednesday evening is 10 hours
- **THEN** the task is marked tight

#### Scenario: Late task
- **WHEN** a task with effort `M` (4 h) is due today at 17:00 and only 2 free hours are left today
- **THEN** the task is marked late

#### Scenario: Plenty of time
- **WHEN** a task with effort `S` (2 h) is due in 4 days with 20 free hours until then
- **THEN** the task is marked ok

### Requirement: Capacity indicator
The day view header SHALL show the free time of the displayed day (for today: from now on) as a duration and a small bar relative to the working hours.

#### Scenario: Busy day
- **WHEN** blocking meetings cover 6 of 8 working hours on the displayed day
- **THEN** the header shows "free 2h" with the bar a quarter full

### Requirement: Planning updates live
Free time, states and the capacity indicator SHALL update without user action when appointments change, when the user changes an override, effort or setting, and as time passes.

#### Scenario: Meeting declined in Outlook
- **WHEN** the user declines a meeting and the change reaches the system calendar
- **THEN** the free time and the task states update in the day view
