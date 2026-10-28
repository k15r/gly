# Spec Delta

## ADDED Requirements

### Requirement: Remaining effort from parts
When at least one part of a task has an effort, the task's remaining effort SHALL be the sum of the efforts of its open parts, and planning SHALL use it; parts without an effort SHALL count as zero and be shown as unestimated on the task page. For such a task, "done for today" and setting the remaining effort by hand SHALL NOT be offered. A task whose parts have no effort SHALL keep its own effort and recorded work.

#### Scenario: Ticking off a part
- **WHEN** a task has the open parts "Outline" (S, 2 h), "Draft" (L, 1 day) and "Review" (S, 2 h), and the user ticks off "Outline"
- **THEN** its remaining effort is 1 day 2 hours, and the day view plans with that

#### Scenario: Unestimated parts
- **WHEN** a task with effort `L` has two parts without effort
- **THEN** planning keeps using the task's own effort and recorded work, and "done for today" is offered as before
