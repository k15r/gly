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

### Requirement: Edit a task
The system SHALL let the user change every task field. Edits SHALL be saved without an explicit save step, inline in lists (such as priority or completion) and on the task page; each field change and each notes edit session SHALL be one undo step. Creating a new task SHALL use a form with an explicit confirm.

#### Scenario: Change priority inline
- **WHEN** the user changes a task's priority from `normal` to `urgent` in the list
- **THEN** the change is saved immediately and the list re-sorts

#### Scenario: Edit on the task page
- **WHEN** the user opens a task and changes its due date, then its notes, then leaves the page
- **THEN** both changes are saved without a save button, and two Undo steps revert them

## ADDED Requirements

### Requirement: Task page
Opening a task (from a list, the day view, the tag tree, a link, a backlink or search) SHALL show it in the main area, laid out like a page: the title; a row with completion, priority, due date, status/snooze and tags; the notes with the read view and editing (⌘E); and its backlinks. It SHALL take part in back/forward navigation.

#### Scenario: Open a task from a link
- **WHEN** the user follows a link to a task from a page
- **THEN** the task page opens in the main area with its notes and backlinks, and ⌘[ returns to the page

#### Scenario: Task backlinks
- **WHEN** two pages link to a task
- **THEN** the task page lists both under backlinks with excerpts
