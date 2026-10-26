# Spec Delta

## MODIFIED Requirements

### Requirement: Task fields
A task SHALL have: title; notes (markdown text with links, edited with the markdown editor); status (`open`, `snoozed`, `done`, `dropped`); priority (`none`, `low`, `normal`, `high`, `urgent`); optional due date with optional time; optional snooze-until date; tags. The system SHALL record when a task was created and last modified, and by whom.

#### Scenario: Due date without time
- **WHEN** the user sets a due date of 30 October without a time
- **THEN** the task is due on 30 October for the whole day

#### Scenario: Due date with time
- **WHEN** the user sets a due date of 30 October 14:00
- **THEN** the task is due at 14:00 local time on 30 October

#### Scenario: Notes link to a page
- **WHEN** the user links the page "Atlas architecture" in a task's notes
- **THEN** the link opens the page, and the page lists the task under its backlinks
