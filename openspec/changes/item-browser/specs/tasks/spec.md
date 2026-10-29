# Spec Delta

## MODIFIED Requirements

### Requirement: Task list
The Tasks view of the item browser SHALL be the task list: by default it shows all `open` tasks (and snoozed tasks whose snooze date has arrived), sorted by priority (urgent first), then due date (earliest first, tasks without due date last), then creation time. Tasks snoozed until a later date SHALL be listed too, sorted like any other task and marked with their snooze date; their due date is unchanged. `done` and `dropped` tasks SHALL be shown through the status filter.

#### Scenario: Default sorting
- **WHEN** there are an urgent task without due date, a normal task due tomorrow and a normal task due today
- **THEN** the list shows the urgent task, then the normal task due today, then the normal task due tomorrow

#### Scenario: Snoozed tasks stay visible
- **WHEN** an urgent task due today is snoozed until Wednesday
- **THEN** the list still shows it at its usual position, marked "until Wed", with its due date still today

#### Scenario: Show completed tasks
- **WHEN** the user sets the status filter of Tasks to `status:done`
- **THEN** the list shows completed tasks, most recently completed first
