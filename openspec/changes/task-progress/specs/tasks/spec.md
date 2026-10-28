# Spec Delta

## ADDED Requirements

### Requirement: Remaining effort
A task with an effort SHALL have a remaining effort: its effort minus the work recorded on it per day, never below zero. Setting the remaining effort directly SHALL record the difference as work of that day, which may be negative. Changing the effort SHALL keep the recorded work. A task without an effort SHALL have no remaining effort.

#### Scenario: Effort changed later
- **WHEN** a task with effort `XL` has 1 day of recorded work and the user changes its effort to `L` (1 working day)
- **THEN** its remaining effort is 0, and its recorded work is unchanged

#### Scenario: More left than thought
- **WHEN** a task with effort `L` has 4 hours left and the user sets its remaining effort to 6 hours
- **THEN** its remaining effort is 6 hours, recorded as an adjustment of minus 2 hours for today

### Requirement: Progress on the task page
The task page SHALL show the remaining effort next to the effort, the recorded work per day, a way to set the remaining effort, and a way to reset it to the full effort. Task rows SHALL show the remaining effort next to the effort chip when work has been recorded.

#### Scenario: Set what's left
- **WHEN** a task has effort `XL` (3 working days) and the user sets its remaining effort to 1 day 4 hours on the task page
- **THEN** the task shows "1d 4h left" on its page and in its rows, and its recorded work shows 1 day 4 hours for today

#### Scenario: Reset
- **WHEN** the user resets the remaining effort of a task with recorded work
- **THEN** its remaining effort equals its effort again, and the recorded work is gone (undo brings it back)
