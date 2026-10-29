# Design

## Context

- Meeting notes are items of kind `event_note`. A series shares one document with dated sections (meeting-pages N1, N4). The meeting page edits them in the live-preview editor (`MeetingPageView`).
- Checklist items are parsed by `ChecklistParts` (subtasks S1). Links are `[label](gly://item/<id>)`, indexed in `link_index`; backlinks come from `LinkQueries.backlinks(db, to:)`.
- Commands run in one `Batch` each, so one command = one undo step.

## Goals / Non-Goals

**Goals:**
- One click from action item to planned task, one undo back.
- What's left from earlier meetings is visible in the next one.

**Non-Goals:**
- Making tasks automatically from every checklist item.
- Assigning items to people (`@alex`): no owner model yet.
- An MCP tool for it. Agents can already create tasks and edit notes.

## Decisions

### A1: Command `makeTaskFromNotes(notesID:, line:, text:)`

One batch:
1. Check that the notes' line number `line` still reads `- [ ] <text>` (the caller sends what it showed); otherwise fail with `conflict`.
2. Create a task titled `text`, without an estimate suffix. A trailing size estimate becomes the task's effort, a duration is dropped (subtasks syntax). The task gets the notes' tags and the notes "From [<meeting title>](gly://item/<notesID>)".
3. Replace the line with `- [<title>](gly://item/<taskID>)`, keeping its indentation.

The link index then has the task → notes link, which A2 uses.

**Alternative: keep the checkbox and link the task next to it.** Rejected: two done-marks for one thing (the checkbox and the task) would drift apart.

### A2: Open action items

`MeetingNotes.openActionItems(db, notesID:)` returns the backlinks of the notes item whose source is an open task, ordered by creation. A series has one notes item, so its earlier meetings' tasks are included automatically.

### A3: The meeting page panel

Between the header and the notes, a collapsible "Action items" section with two parts:
- **"In these notes":** the open checklist items parsed from the notes, each with a "Make task" button (disabled when writing isn't possible).
- **"Open tasks":** `TaskRow`s from A2.

The section is hidden when both are empty.

## Risks / Trade-offs

- **[Line identity]** The notes may change between showing and clicking. → The command checks the line's text (A1 step 1) and fails visibly instead of rewriting the wrong line.
- **[Agent-written items]** Agents' checklist items work the same way.
