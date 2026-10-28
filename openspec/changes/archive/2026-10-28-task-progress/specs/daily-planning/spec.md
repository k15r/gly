# Spec Delta

## ADDED Requirements

### Requirement: Planning uses the remaining effort
Wherever planning uses a task's effort (work needed, "can't fit", start by, forecasts of later days, the snooze warning, the sum in the Today header), it SHALL use the task's remaining effort instead. A task whose remaining effort is zero SHALL need no work; if it is due that day or overdue it stays in the Today list with nothing needed. Forecasts SHALL count the work recorded so far, and none beyond it.

#### Scenario: Day two of a big task
- **WHEN** a task with effort `XL` (3 working days) is due in 3 working days, the user recorded 1 day of work on it yesterday, and the 2 remaining working days until its due date are free
- **THEN** today's list shows it needing work today, and not as "can't fit"

### Requirement: Record today's part
A row in the Today or Coming up list of today's view whose task needs work today SHALL offer "done for today". Choosing it SHALL record the work needed today as worked today; while recorded, the row SHALL show that today's part is done, and choosing it again SHALL take the recorded amount back. Later days' forecasts SHALL NOT offer it.

#### Scenario: Tick off today's part
- **WHEN** a task with effort `XL` shows "today ≥ 1d" and the user chooses "done for today"
- **THEN** 1 day of work is recorded for today, the task's remaining effort is 2 days, and its row shows today's part as done

#### Scenario: Take it back
- **WHEN** the user chooses "done for today" again on that row
- **THEN** the recorded day is removed and the task needs 1 day today again
