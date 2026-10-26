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
Each appointment SHALL count as blocking (fully), maybe (half) or free. Without an override, it SHALL be classified from the calendar: cancelled, declined and "free" appointments are free; all-day appointments are free unless marked out of office or busy, which block the whole day; tentative appointments (my response tentative or pending, or marked tentative by the calendar) are maybe; all others block. A blocking override from the user SHALL take precedence.

#### Scenario: Declined meeting
- **WHEN** the user declined a 10:00–11:00 meeting
- **THEN** that hour counts as free time

#### Scenario: Tentative meeting
- **WHEN** an unanswered meeting runs 13:00–14:00
- **THEN** it reduces the free time by 30 minutes

#### Scenario: No response information
- **WHEN** the calendar gives no information about my response to a meeting and marks it busy
- **THEN** it blocks its time

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

### Requirement: Today list
On today's day view, the system SHALL show one "Today" list with the open tasks that are overdue, due today, or need work today so that they can be finished by their due date. Each row SHALL say why it is there (overdue, due today, or the minimum work needed today). The list SHALL be sorted: tasks that can't fit first, then overdue, due today, needs work today; within each group by priority (urgent first), then due date.

#### Scenario: Task needing work today
- **WHEN** a task with effort `XL` (3 working days) is due on Friday and there are 2 free working days after today until then
- **THEN** it appears in the Today list with "today ≥ 1 day"

#### Scenario: Due today without estimate
- **WHEN** a task without effort is due today
- **THEN** it appears in the Today list marked "due today" and "no estimate"

#### Scenario: Can't fit
- **WHEN** a task with effort `M` (4 h) is due today at 17:00 and only 2 free hours are left today
- **THEN** it appears first in the Today list, marked "can't fit"

### Requirement: Work needed today
For a task with an effort, the work needed today SHALL be its effort minus the free time after today until its due date (the end of the due day, or the due time); for tasks due today or overdue it is the whole effort. A task SHALL be marked "can't fit" when its effort is more than the free time from now until its due date. Tasks are evaluated one by one, without sharing free time between them.

#### Scenario: Enough time later
- **WHEN** a task with effort `S` (2 h) is due in 4 days with 20 free hours after today
- **THEN** no work is needed today, and it is not in the Today list

### Requirement: Today's load
The Today list header SHALL show the sum of the work needed today next to today's free time, and SHALL warn by how much the needed work exceeds the free time. Tasks in the list without an estimate SHALL be counted separately ("+ 2 without estimate").

#### Scenario: Overbooked day
- **WHEN** the Today list needs 7 hours of work and 5.5 hours are free today
- **THEN** the header shows "needs 7h · free 5h 30m" and "1h 30m short"

### Requirement: Coming up
Below the Today list, the system SHALL list the other open tasks due within the next N days (N configurable, default 5, switchable in the day view; snoozed tasks only from their snooze date), each with the last day it can be started and still be finished ("start by"), computed from its effort and the free time per day; tasks without effort SHALL be listed last, marked "no estimate". The list SHALL be sorted by start-by day, then due date.

#### Scenario: Start by
- **WHEN** a task with effort `L` (1 working day) is due Thursday, Wednesday is fully free and Thursday is fully booked
- **THEN** it shows "start by Wed"

#### Scenario: Horizon
- **WHEN** the horizon is 5 days and a task is due in 4 days and another in 8 days
- **THEN** only the first appears (in Today or Coming up)

#### Scenario: Switch the horizon
- **WHEN** the user switches the horizon in the day view to 14 days
- **THEN** tasks due in the next 14 days are considered, and the choice is kept

### Requirement: Capacity indicator
The day view header SHALL show the free time of the displayed day (for today: from now on) as a duration and a small bar relative to the working hours.

#### Scenario: Busy day
- **WHEN** blocking meetings cover 6 of 8 working hours on the displayed day
- **THEN** the header shows "free 2h" with the bar a quarter full

### Requirement: Planning updates live
Free time, the Today and Coming up lists and the capacity indicator SHALL update without user action when appointments change, when the user changes an override, effort or setting, and as time passes.

#### Scenario: Meeting declined in Outlook
- **WHEN** the user declines a meeting and the change reaches the system calendar
- **THEN** the free time and the work needed today update in the day view
