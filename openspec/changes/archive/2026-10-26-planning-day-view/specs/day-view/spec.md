# Spec Delta

## MODIFIED Requirements

### Requirement: Tasks for the day
The day view SHALL show the open tasks due on the displayed day. When the displayed day is today, the tasks SHALL be shown as the Today list of daily planning: overdue tasks (marked as overdue), tasks due today, and tasks that need work today. A task snoozed until a later date SHALL NOT appear, on the current day or any future day, until its snooze date has arrived; then it is shown like any open task. On other days, tasks SHALL be sorted by priority (urgent first), then by due time.

#### Scenario: Due and overdue tasks today
- **WHEN** today has an urgent task due today, a normal task due today, and a normal task due yesterday that is still open
- **THEN** the Today list shows the overdue normal task marked "overdue" first, then the urgent and the normal task due today, in that order

#### Scenario: Future day
- **WHEN** the user views tomorrow
- **THEN** only tasks due tomorrow appear, and no overdue tasks

#### Scenario: Snoozed until tomorrow
- **WHEN** a task due today is snoozed until tomorrow and the user views tomorrow
- **THEN** the task appears neither today nor on tomorrow's view, and when tomorrow becomes today it appears marked "overdue"
