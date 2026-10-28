# daily-planning Specification

## Purpose

Shows each day what to work on so that tasks are done by their due dates, based on how much work each task is and how much free time the calendar really leaves.

## Requirements

### Requirement: Effort sizes
A task MAY have an effort of `XS`, `S`, `M`, `L` or `XL`. Each size SHALL stand for an amount of working time that the user can configure in Settings; the defaults SHALL be 30 minutes, 2 hours, 4 hours, 1 working day and 3 working days, where a working day is the length of the working hours.

#### Scenario: Default sizes
- **WHEN** the working hours are 09:00–17:00 and nothing was configured
- **THEN** `L` stands for 8 hours and `XL` for 24 hours of working time

#### Scenario: Configured size
- **WHEN** the user sets `M` to 3 hours in Settings
- **THEN** every task with effort `M` counts as 3 hours of work

### Requirement: Working hours
The system SHALL use one configurable daily working-hours window (default 09:00–17:00) on a configurable set of working days (default Monday to Friday), the same on every working day. Free time SHALL only be counted inside this window on working days; a non-working day SHALL have no free time.

#### Scenario: Change working hours
- **WHEN** the user sets working hours to 08:00–16:00
- **THEN** free time for every working day is counted between 08:00 and 16:00

#### Scenario: Weekend
- **WHEN** working days are Monday to Friday and a task with effort `L` (1 working day) is due Monday, which is fully booked
- **THEN** it shows "start by Fri", not Saturday or Sunday, and Saturday's and Sunday's day views show "free 0m"

#### Scenario: Change working days
- **WHEN** the user adds Saturday to the working days
- **THEN** Saturday counts with the working hours like any other working day

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
On the view of today or a later day, the system SHALL show one list of the open tasks that are overdue, due that day, or need work that day, seen from that day and assuming nothing is done before it. It SHALL be titled "Today", or with the date on a later day. Each row SHALL say why it is there (overdue, due that day, or the minimum work needed that day). Sorted: can't fit first, then overdue, due that day, needs work; within each group by priority (urgent first), then due date.

#### Scenario: Task needing work today
- **WHEN** a task with effort `XL` (3 working days) is due on Friday and there are 2 free working days after today until then
- **THEN** it appears in the Today list with "today ≥ 1 day"

#### Scenario: Due today without estimate
- **WHEN** a task without effort is due today
- **THEN** it appears in the Today list marked "due today" and "no estimate"

#### Scenario: Can't fit
- **WHEN** a task with effort `M` (4 h) is due today at 17:00 and only 2 free hours are left today
- **THEN** it appears first in the Today list, marked "can't fit"

#### Scenario: Forecast for a later day
- **WHEN** a task with effort `XL` (3 working days) is due on Friday, today is Monday, and the user views Wednesday, which has a free working day followed by a fully free Thursday and Friday
- **THEN** Wednesday's list, titled "Wed 28 Oct", shows the task with "Wed ≥ 1 day"

#### Scenario: Nothing to do on a later day
- **WHEN** no task is overdue, due or needs work on a later day the user views
- **THEN** the list is titled with that day's date and says that nothing needs work that day

### Requirement: Work needed today
For a task with an effort, the work needed on the planned day (today or a later day) SHALL be its effort minus the free time after that day until its due date; for tasks due that day or overdue it is the whole effort. A task SHALL be "can't fit" when its effort exceeds the free time from the start of planning (now for today, else the start of the day) until its due date, or for an overdue task until the end of the planned day. Tasks are evaluated one by one, without sharing free time.

#### Scenario: Enough time later
- **WHEN** a task with effort `S` (2 h) is due in 4 days with 20 free hours after today
- **THEN** no work is needed today, and it is not in the Today list

#### Scenario: Overdue but fits the day
- **WHEN** a task with effort `S` (2 h) was due yesterday and 8 hours are free on the planned day
- **THEN** it is listed as "overdue" with 2 h needed, and not as "can't fit"

#### Scenario: Overdue and too big for the day
- **WHEN** a task with effort `L` (1 working day) was due yesterday and only 3 hours are free on the planned day
- **THEN** it is listed as "overdue" and "can't fit"

### Requirement: Today's load
The header of the Today list SHALL show the sum of the work needed that day next to that day's free time (for today from now on, for a later day its whole working time), and SHALL warn by how much the needed work exceeds the free time. Tasks in the list without an estimate SHALL be counted separately ("+ 2 without estimate").

#### Scenario: Overbooked day
- **WHEN** the Today list needs 7 hours of work and 5.5 hours are free today
- **THEN** the header shows "needs 7h · free 5h 30m" and "1h 30m short"

### Requirement: Coming up
Below the Today list, the system SHALL list the other open tasks due within the N days after the displayed day (N configurable, default 5, switchable in the day view; snoozed tasks only from their snooze date), each with the last day it can be started and still be finished ("start by"), computed from its effort and the free time per day; tasks without effort SHALL be listed last, marked "no estimate". The list SHALL be sorted by start-by day, then due date.

#### Scenario: Start by
- **WHEN** a task with effort `L` (1 working day) is due Thursday, Wednesday is fully free and Thursday is fully booked
- **THEN** it shows "start by Wed"

#### Scenario: Horizon
- **WHEN** the horizon is 5 days and a task is due in 4 days and another in 8 days
- **THEN** only the first appears (in Today or Coming up)

#### Scenario: Switch the horizon
- **WHEN** the user switches the horizon in the day view to 14 days
- **THEN** tasks due in the next 14 days are considered, and the choice is kept

#### Scenario: Horizon from a later day
- **WHEN** the horizon is 5 days and the user views the day after tomorrow
- **THEN** Coming up lists tasks due up to 5 days after that day

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

### Requirement: Back from snooze
On the day a snoozed task comes back (its snooze date), its row in the Today or Coming up list of that day's view SHALL be marked "back from snooze", with a tooltip naming the snooze date and stating that the due date is unchanged. This SHALL hold for today and for a later day's forecast. On other days the mark SHALL NOT appear.

#### Scenario: Back today
- **WHEN** a task due Friday was snoozed until today
- **THEN** today's list shows it marked "back from snooze", and the tooltip says it was snoozed until today and is still due Friday

#### Scenario: Forecast of the return
- **WHEN** a task is snoozed until Wednesday and the user views Wednesday
- **THEN** Wednesday's view shows it marked "back from snooze"; Thursday's view shows it without the mark

### Requirement: Snoozed tasks summary
Below Coming up, the day view of today or a later day SHALL show how many open tasks are still snoozed on that day ("2 snoozed"), if any. Clicking it SHALL show those tasks with their snooze date and due date, sorted by snooze date; choosing one SHALL open it.

#### Scenario: See snoozed tasks
- **WHEN** two tasks are snoozed until next week and the user clicks "2 snoozed"
- **THEN** a list shows both with "until <day>" and their due dates, and clicking one opens its task page

#### Scenario: Snoozed until the viewed day
- **WHEN** a task is snoozed until Wednesday and the user views Wednesday
- **THEN** it is not counted as snoozed there, because it is back that day
