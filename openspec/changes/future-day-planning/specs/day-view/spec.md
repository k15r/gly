# Spec Delta

## MODIFIED Requirements

### Requirement: Tasks for the day
The day view SHALL show the open tasks that matter on the displayed day. When the displayed day is today or a later day, the tasks SHALL be shown as the Today list of daily planning, seen from that day: overdue tasks (open tasks due before that day, marked as overdue), tasks due that day, and tasks that need work that day. A task snoozed until a later date SHALL NOT appear on any day before its snooze date; from its snooze date on it is shown like any open task. On past days, the day view SHALL show the open tasks due that day, sorted by priority (urgent first), then by due time.

#### Scenario: Due and overdue tasks today
- **WHEN** today has an urgent task due today, a normal task due today, and a normal task due yesterday that is still open
- **THEN** the Today list shows the overdue normal task marked "overdue" first, then the urgent and the normal task due today, in that order

#### Scenario: Future day
- **WHEN** a task due today is still open and the user views tomorrow
- **THEN** tomorrow's list shows it marked "overdue", next to the tasks due tomorrow and those that need work tomorrow

#### Scenario: Snoozed until tomorrow
- **WHEN** a task due today is snoozed until tomorrow and the user views today and then tomorrow
- **THEN** the task does not appear today, and tomorrow's view shows it marked "overdue" and "back from snooze"

#### Scenario: Past day
- **WHEN** the user views yesterday
- **THEN** it shows the open tasks due yesterday as a plain list, without planning sections
