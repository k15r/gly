# Spec Delta

## MODIFIED Requirements

### Requirement: Working hours
The system SHALL use one configurable daily working-hours window (default 09:00–17:00) on a configurable set of working days (default Monday to Friday), the same on every working day. Free time SHALL only be counted inside this window on working days; a non-working day SHALL have no free time.

#### Scenario: Change working hours
- **WHEN** the user sets working hours to 08:00–16:00
- **THEN** free time for every working day is counted between 08:00 and 16:00

#### Scenario: Weekend
- **WHEN** working days are Monday to Friday and a task with effort `L` (1 working day) is due Monday, which is fully booked
- **THEN** it shows "start by Fri", not Saturday or Sunday, and Saturday's and Sunday's day views show "free 0m"

#### Scenario: Change working days
- **WHEN** the user adds Saturday to the working days
- **THEN** Saturday counts with the working hours like any other working day
