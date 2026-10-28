# Spec Delta

## ADDED Requirements

### Requirement: Parts of a task
A task SHALL be able to have an ordered list of parts, each with a title, an optional effort (`XS`, `S`, `M`, `L`, `XL`) and a done mark. The task page SHALL let the user add, rename, estimate, tick off, reorder and delete parts; each change SHALL be one undo step. Task rows SHALL show how many parts are done ("2/5"). When all parts are done and the task is still open, the task page SHALL offer to complete the task; the task SHALL NOT be completed automatically. Search SHALL find a task by the titles of its parts.

#### Scenario: Break a task down
- **WHEN** the user adds the parts "Outline" (S), "Draft" (L) and "Review" (S) to a task
- **THEN** the task page lists them in that order, and the task's rows show "0/3"

#### Scenario: All parts done
- **WHEN** the user ticks off the last open part of an open task
- **THEN** the rows show "3/3", the task stays open, and its page offers "Complete task"

#### Scenario: Find by part
- **WHEN** the user searches for "Draft"
- **THEN** the task with the part "Draft" is among the results
