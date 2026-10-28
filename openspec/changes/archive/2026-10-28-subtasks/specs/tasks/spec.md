# Spec Delta

## ADDED Requirements

### Requirement: Parts of a task
The checklist items (`- [ ]`, `- [x]`) in a task's notes SHALL be its parts, in their order in the text; items inside code blocks SHALL NOT count. An item MAY end with an estimate in parentheses: an effort size `(XS)`, `(S)`, `(M)`, `(L)`, `(XL)`, or a duration of days, hours and minutes such as `(30m)`, `(2h)`, `(1d)` or `(1d 4h)`, where a day is one working day. The estimate SHALL NOT be part of the item's title. Task rows SHALL show how many parts are done ("2/5").

#### Scenario: Break a task down
- **WHEN** the notes of a task contain `- [ ] Outline (S)`, `- [ ] Draft (1d)` and `- [ ] Review (90m)`
- **THEN** the task has the parts "Outline", "Draft" and "Review" in that order, with estimates of 2 hours, one working day and 1 hour 30 minutes, and its rows show "0/3"

#### Scenario: Item without estimate
- **WHEN** the notes contain `- [ ] Book room`
- **THEN** "Book room" is a part without an estimate

### Requirement: All parts done
When all parts of an open task are done, the task page SHALL offer to complete the task; the task SHALL NOT be completed automatically.

#### Scenario: Last part ticked off
- **WHEN** the user ticks off the last open checklist item of an open task
- **THEN** the rows show "3/3", the task stays open, and its page offers "Complete task"
