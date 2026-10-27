# trash Specification

## Purpose

Shows what was deleted (pages and tasks, by the user or by agents) and brings it back, so no delete is final and an agent's mistake can be fixed from the app.

## Requirements

### Requirement: Trash contents
The sidebar SHALL offer a Trash, with the number of items deleted in the last 30 days, that lists deleted pages and tasks, most recently deleted first. Each entry SHALL show the kind (icon), title, tags, the start of the text, when it was deleted and who deleted it (the user or the agent by name). Selecting an entry SHALL show its title, tags and text read-only.

#### Scenario: Agent deletes a page
- **WHEN** Claude Code deletes the page "Goals" tagged `person/bob`
- **THEN** the Trash lists "Goals" at the top with `person/bob`, the start of its text, "deleted just now by Claude Code"

#### Scenario: Preview
- **WHEN** the user selects a deleted page in the Trash
- **THEN** its text is shown read-only, and links in it can be followed

### Requirement: Deleted items are kept
Deleted pages and tasks SHALL never be erased, except by erasing all data ("Erase all data"). The Trash SHALL show the items deleted in the last 30 days and offer to show older ones, with their number.

#### Scenario: Older deletes
- **WHEN** one task was deleted 40 days ago and one page yesterday
- **THEN** the Trash lists the page and "Show older (1)"; choosing it lists the task too

### Requirement: Restore from the Trash
The user SHALL be able to restore a deleted page or task from the Trash, whoever deleted it. The item SHALL return with the fields and tags it had when it was deleted, appear again everywhere, and links to it SHALL work again. A restore SHALL be one undo step of the user who restored it.

#### Scenario: Restore an agent's delete
- **WHEN** Joule deleted the task "Call the venue" tagged `project/atlas` and the user restores it from the Trash
- **THEN** the task is open again with its due date and the tag `project/atlas`, it leaves the Trash, and links to it work again

#### Scenario: Undo a restore
- **WHEN** the user restores a page and then chooses Undo
- **THEN** the page is deleted again and back in the Trash

### Requirement: Erase all data
Settings SHALL offer to erase all data after a confirmation: all tasks, pages, tags and tag descriptions, appointment overrides, the trash and the change history are removed for good, and no copy is kept. Settings SHALL stay. Agents SHALL NOT be able to erase all data.

#### Scenario: Erase and start over
- **WHEN** the user chooses "Erase All Data…" in Settings and confirms
- **THEN** all lists, the tag tree and the Trash are empty, Undo has nothing to undo, working hours and agent access are unchanged, and new tasks can be created as usual

#### Scenario: Cancel
- **WHEN** the user chooses "Erase All Data…" and then Cancel
- **THEN** nothing changes
