# Spec Delta

## ADDED Requirements

### Requirement: Parts over MCP
Task results SHALL include the task's parts in order, each with title, estimate in minutes (or null) and done, derived from the checklist in its notes. Agents SHALL change parts by changing the notes; the tool descriptions SHALL explain the checklist and estimate syntax.

#### Scenario: Agent breaks a task down
- **WHEN** an agent creates a task with notes containing three checklist items, two of them with an estimate
- **THEN** the task result lists the three parts in order, and its remaining effort is the sum of the two estimates

#### Scenario: Agent ticks off a part
- **WHEN** an agent updates a task's notes, changing one item from `- [ ]` to `- [x]`
- **THEN** that part is done in the task result and in the app
