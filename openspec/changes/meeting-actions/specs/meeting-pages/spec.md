# Spec Delta

## ADDED Requirements

### Requirement: Action items become tasks
On a meeting page, each open checklist item in the meeting notes SHALL offer "Make task". Choosing it SHALL create a task titled with the item's text, carrying the meeting notes' tags and notes that link back to the meeting, and SHALL replace the item's line in the notes with a list item linking to the new task. Both SHALL be one change that one undo reverts.

#### Scenario: Make a task
- **WHEN** the notes of a meeting tagged `project/atlas` contain `- [ ] Send agenda` and the user chooses "Make task" for it
- **THEN** an open task "Send agenda" tagged `project/atlas` exists whose notes link to the meeting, and the notes line is now a link to that task

#### Scenario: Undo
- **WHEN** the user presses ⌘Z right after making the task
- **THEN** the task is gone and the notes show `- [ ] Send agenda` again

### Requirement: Open action items
A meeting page SHALL list the open tasks whose notes link to its meeting notes, for a series those from all its meetings, with the usual task row actions.

#### Scenario: Next meeting of a series
- **WHEN** a task was made from last week's 1:1 notes and is still open, and the user opens this week's 1:1
- **THEN** the meeting page lists that task under open action items; once it is done, it is no longer listed
