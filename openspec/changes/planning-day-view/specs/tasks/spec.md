# Spec Delta

## MODIFIED Requirements

### Requirement: Task fields
A task SHALL have: title; notes (markdown text with links, edited with the markdown editor); status (`open`, `snoozed`, `done`, `dropped`); priority (`none`, `low`, `normal`, `high`, `urgent`); optional due date with optional time; optional snooze-until date; optional effort (`XS`, `S`, `M`, `L`, `XL`); tags. The system SHALL record when a task was created and last modified, and by whom.

#### Scenario: Due date without time
- **WHEN** the user sets a due date of 30 October without a time
- **THEN** the task is due on 30 October for the whole day

#### Scenario: Due date with time
- **WHEN** the user sets a due date of 30 October 14:00
- **THEN** the task is due at 14:00 local time on 30 October

#### Scenario: Notes link to a page
- **WHEN** the user links the page "Atlas architecture" in a task's notes
- **THEN** the link opens the page, and the page lists the task under its backlinks

#### Scenario: Effort
- **WHEN** the user sets a task's effort to `M`
- **THEN** the task shows an `M` chip in lists and on its task page

### Requirement: Task page
Opening a task (from a list, the day view, the tag tree, a link, a backlink or search) SHALL show it in the main area, laid out like a page: the title; a row with completion, priority, effort, due date, status/snooze and tags; the notes with the read view and editing (⌘E); and its backlinks. It SHALL take part in back/forward navigation.

#### Scenario: Open a task from a link
- **WHEN** the user follows a link to a task from a page
- **THEN** the task page opens in the main area with its notes and backlinks, and ⌘[ returns to the page

#### Scenario: Task backlinks
- **WHEN** two pages link to a task
- **THEN** the task page lists both under backlinks with excerpts

#### Scenario: Set effort on the task page
- **WHEN** the user picks `L` in the effort control of the task page
- **THEN** the effort is saved at once as one undo step
