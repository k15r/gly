# Spec Delta

## MODIFIED Requirements

### Requirement: Today list
On today's day view and on the view of any later day, the system SHALL show one list with the open tasks that are overdue, due that day, or need work that day so that they can be finished by their due date, seen from that day and assuming nothing is done before it. The list SHALL be titled "Today" on today's view and with the date (e.g. "Thu 29 Oct") on a later day; when it is empty it SHALL say that nothing needs work today or that day. Each row SHALL say why it is there (overdue, due that day, or the minimum work needed that day, e.g. "today ≥ 1 day" or "Wed ≥ 1 day"). The list SHALL be sorted: tasks that can't fit first, then overdue, due that day, needs work that day; within each group by priority (urgent first), then due date.

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

### Requirement: Work needed today
For a task with an effort, the work needed on the planned day (today, or the later day being viewed) SHALL be its effort minus the free time after that day until its due date (the end of the due day, or the due time); for tasks due that day or overdue it is the whole effort. A task SHALL be marked "can't fit" when its effort is more than the free time from the start of the planning (now for today, the start of the day for a later day) until its due date; for an overdue task, whose due date has passed, until the end of the planned day. Tasks are evaluated one by one, without sharing free time between them.

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

## ADDED Requirements

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
