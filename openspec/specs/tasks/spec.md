# tasks Specification

## Purpose

Lets the user capture and maintain their own tasks in gly, with status, priority, due date, notes and tags, stored durably with a history of every change.

## Requirements

### Requirement: Create a task
The system SHALL let the user create a task with a required, non-empty title. A new task SHALL have status `open` and priority `none` unless the user chooses otherwise. Notes, due date and tags SHALL be optional.

#### Scenario: Minimal task
- **WHEN** the user creates a task titled "Approve load-test budget"
- **THEN** the task exists with status `open`, priority `none`, no due date and no tags

#### Scenario: Empty title
- **WHEN** the user tries to save a task without a title
- **THEN** the task is not saved and the title field is marked as required

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

### Requirement: Edit a task
The system SHALL let the user change every task field. Edits SHALL be saved without an explicit save step, inline in lists (such as priority or completion) and on the task page; each field change and each notes edit session SHALL be one undo step. Creating a new task SHALL use a form with an explicit confirm.

#### Scenario: Change priority inline
- **WHEN** the user changes a task's priority from `normal` to `urgent` in the list
- **THEN** the change is saved immediately and the list re-sorts

#### Scenario: Edit on the task page
- **WHEN** the user opens a task and changes its due date, then its notes, then leaves the page
- **THEN** both changes are saved without a save button, and two Undo steps revert them

### Requirement: Task status transitions
The system SHALL support completing (`done`), reopening (`open`), snoozing until a date (`snoozed`), and dropping (`dropped`) a task. A snoozed task SHALL become `open` again automatically on its snooze date.

#### Scenario: Snooze until Monday
- **WHEN** the user snoozes a task until Monday
- **THEN** the task is hidden from the day view until Monday and marked "until Mon" in the task list, and on Monday it is `open` again

#### Scenario: Reopen a completed task
- **WHEN** the user reopens a `done` task
- **THEN** its status is `open` again

### Requirement: Delete a task
The system SHALL let the user delete a task. A deleted task SHALL disappear from all views but SHALL remain recoverable through undo and from the Trash.

#### Scenario: Delete and undo
- **WHEN** the user deletes a task and then chooses Undo
- **THEN** the task returns with all its fields and tags

#### Scenario: Delete and restore later
- **WHEN** the user deletes a task, makes other changes, and later restores the task from the Trash
- **THEN** the task returns with all its fields and tags, and the other changes stay

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
- **WHEN** the user creates a task, quits gly and opens it again
- **THEN** the task is still there unchanged

#### Scenario: History records the writer
- **WHEN** the user changes a task's priority on the Mac
- **THEN** the history entry records the old and new priority and the writer `user@<this Mac>`

### Requirement: Changes appear everywhere immediately
A change to a task SHALL be reflected in every open view (day view, task list, tag filter) without manual refresh, including changes made by another gly process writing to the same store.

#### Scenario: Complete in the task list
- **WHEN** the user completes a task in the task list
- **THEN** it also disappears from the day view at the same time

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

### Requirement: Snooze shows its cost
Where the user snoozes a task from a menu, the snooze options SHALL say that the task's due date stays as it is, and each option SHALL warn when the task, coming back on that date, would no longer fit before its due date (its effort is more than the free time from the start of the return day until its due date). Tasks without due date or without effort SHALL show no warning.

#### Scenario: Snooze too long
- **WHEN** a task with effort `XL` (3 working days) is due Friday, today is Monday, all days until Friday are free, and the user opens its snooze options
- **THEN** the options state "due Fri stays", "Snooze until Tomorrow" shows no warning, and "Snooze until Next Monday" warns that the task won't fit anymore

#### Scenario: No estimate
- **WHEN** a task without effort is due Friday and the user opens its snooze options
- **THEN** the options state "due Fri stays" and show no warning

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
