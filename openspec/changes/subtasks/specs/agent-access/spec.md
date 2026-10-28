# Spec Delta

## ADDED Requirements

### Requirement: Parts over MCP
Task results SHALL include the task's parts in order, each with id, title, effort (or null) and done. `create_task` SHALL accept parts, and `update_task` SHALL accept a list of parts that replaces the current list: parts given with an existing id are kept and updated, parts without id are added, and parts left out are removed. All changes of one call SHALL be one change in the history.

#### Scenario: Agent breaks a task down
- **WHEN** an agent calls `create_task` with three parts, two of them with an effort
- **THEN** the task has the three parts in that order, and its remaining effort is the sum of the two efforts

#### Scenario: Agent ticks off a part
- **WHEN** an agent calls `update_task` with the task's parts, one of them now `done: true`
- **THEN** that part is done, the others are unchanged, and the change is one step in the history attributed to the agent
