# Spec Delta

## ADDED Requirements

### Requirement: Snooze shows its cost
Where the user snoozes a task from a menu, the snooze options SHALL say that the task's due date stays as it is, and each option SHALL warn when the task, coming back on that date, would no longer fit before its due date (its effort is more than the free time from the start of the return day until its due date). Tasks without due date or without effort SHALL show no warning.

#### Scenario: Snooze too long
- **WHEN** a task with effort `XL` (3 working days) is due Friday, today is Monday, all days until Friday are free, and the user opens its snooze options
- **THEN** the options state "due Fri stays", "Snooze until Tomorrow" shows no warning, and "Snooze until Next Monday" warns that the task won't fit anymore

#### Scenario: No estimate
- **WHEN** a task without effort is due Friday and the user opens its snooze options
- **THEN** the options state "due Fri stays" and show no warning
