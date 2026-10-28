# Spec Delta

## ADDED Requirements

### Requirement: Remaining effort from parts
When at least one part of a task has an estimate, the task's remaining effort SHALL be the sum of the estimates of its open parts, and planning SHALL use it; parts without an estimate count as zero and are shown as unestimated on the task page. For such a task, "done for today" and setting the remaining effort by hand SHALL NOT be offered. A task whose parts have no estimates SHALL keep its own effort and recorded work.

#### Scenario: Ticking off a part
- **WHEN** a task has the open parts `Outline (S)`, `Draft (L)` and `Review (2h)`, and the user ticks off "Outline"
- **THEN** its remaining effort is 1 day 2 hours, and the day view plans with that

#### Scenario: Unestimated parts
- **WHEN** a task with effort `L` has two checklist items without estimates
- **THEN** planning keeps using the task's own effort and recorded work, and "done for today" is offered as before
