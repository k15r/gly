# Spec Delta

## Purpose

Lets the user capture and maintain their own tasks in WorkDash, with status, priority, due date, notes and tags, stored durably with a history of every change.

## ADDED Requirements

### Requirement: Create a task
The system SHALL let the user create a task with a required, non-empty title. A new task SHALL have status `open` and priority `none` unless the user chooses otherwise. Notes, due date and tags SHALL be optional.

#### Scenario: Minimal task
- **WHEN** the user creates a task titled "Approve load-test budget"
- **THEN** the task exists with status `open`, priority `none`, no due date and no tags

#### Scenario: Empty title
- **WHEN** the user tries to save a task without a title
- **THEN** the task is not saved and the title field is marked as required

### Requirement: Task fields
A task SHALL have: title; notes (markdown text, shown and edited as plain text in this version); status (`open`, `snoozed`, `done`, `dropped`); priority (`none`, `low`, `normal`, `high`, `urgent`); optional due date with optional time; optional snooze-until date; tags. The system SHALL record when a task was created and last modified, and by whom.

#### Scenario: Due date without time
- **WHEN** the user sets a due date of 30 October without a time
- **THEN** the task is due on 30 October for the whole day

#### Scenario: Due date with time
- **WHEN** the user sets a due date of 30 October 14:00
- **THEN** the task is due at 14:00 local time on 30 October

### Requirement: Edit a task
The system SHALL let the user change every task field. Edits SHALL be saved without an explicit save step for inline edits (such as priority or completion) and with an explicit confirm for the edit form.

#### Scenario: Change priority inline
- **WHEN** the user changes a task's priority from `normal` to `urgent` in the list
- **THEN** the change is saved immediately and the list re-sorts

### Requirement: Task status transitions
The system SHALL support completing (`done`), reopening (`open`), snoozing until a date (`snoozed`), and dropping (`dropped`) a task. A snoozed task SHALL become `open` again automatically on its snooze date.

#### Scenario: Snooze until Monday
- **WHEN** the user snoozes a task until Monday
- **THEN** the task is hidden from the day view until Monday and marked "until Mon" in the task list, and on Monday it is `open` again

#### Scenario: Reopen a completed task
- **WHEN** the user reopens a `done` task
- **THEN** its status is `open` again

### Requirement: Delete a task
The system SHALL let the user delete a task. A deleted task SHALL disappear from all views but SHALL remain recoverable through undo.

#### Scenario: Delete and undo
- **WHEN** the user deletes a task and then chooses Undo
- **THEN** the task returns with all its fields and tags

### Requirement: Undo and redo
The system SHALL let the user undo the most recent task changes, one change at a time, and redo undone changes, using the standard Undo/Redo commands. A change spanning several fields made in one action SHALL be undone as one step.

#### Scenario: Undo an edit
- **WHEN** the user changes a task's title and due date in the edit form, confirms, and then chooses Undo
- **THEN** both the title and the due date return to their previous values

### Requirement: Task list
The system SHALL provide a task list showing all `open` tasks (and snoozed tasks whose snooze date has arrived), sorted by priority (urgent first), then due date (earliest first, tasks without due date last), then creation time. Tasks snoozed until a later date SHALL be listed too, sorted like any other task and marked with their snooze date; their due date is unchanged. The user SHALL be able to switch to showing `done` and `dropped` tasks.

#### Scenario: Default sorting
- **WHEN** there are an urgent task without due date, a normal task due tomorrow and a normal task due today
- **THEN** the list shows the urgent task, then the normal task due today, then the normal task due tomorrow

#### Scenario: Snoozed tasks stay visible
- **WHEN** an urgent task due today is snoozed until Wednesday
- **THEN** the list still shows it at its usual position, marked "until Wed", with its due date still today

#### Scenario: Show completed tasks
- **WHEN** the user switches to "Done"
- **THEN** the list shows completed tasks, most recently completed first

### Requirement: Durable storage and history
Tasks SHALL be stored persistently and survive app restarts, reboots and quitting the app. Every change SHALL be recorded in a history with the previous value, new value, time and writer. Deleting a task SHALL keep its data recoverable rather than erasing it.

#### Scenario: Restart
- **WHEN** the user creates a task, quits WorkDash and opens it again
- **THEN** the task is still there unchanged

#### Scenario: History records the writer
- **WHEN** the user changes a task's priority on the Mac
- **THEN** the history entry records the old and new priority and the writer `user@<this Mac>`

### Requirement: Changes appear everywhere immediately
A change to a task SHALL be reflected in every open view (day view, task list, tag filter) without manual refresh, including changes made by another WorkDash process writing to the same store.

#### Scenario: Complete in the task list
- **WHEN** the user completes a task in the task list
- **THEN** it also disappears from the day view at the same time
