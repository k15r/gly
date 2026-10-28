# Spec Delta

## ADDED Requirements

### Requirement: Progress over MCP
Task results SHALL include the remaining effort in minutes and the recorded work in minutes (or null for a task without effort). `update_task` SHALL accept `remaining_minutes` to set the remaining effort. An MCP tool `record_work` SHALL record minutes of work on a task for a day (default today), adding to that day's recorded work. Both SHALL be one change in the history and attributed to the agent.

#### Scenario: Agent records work
- **WHEN** an agent calls `record_work` with a task id and `minutes: 120`
- **THEN** the task's recorded work grows by 2 hours, its remaining effort shrinks by 2 hours, and the day view plans with the new remaining effort

#### Scenario: Agent sets what's left
- **WHEN** an agent calls `update_task` with `remaining_minutes: 240` on a task with effort `XL`
- **THEN** the task's remaining effort is 4 hours
