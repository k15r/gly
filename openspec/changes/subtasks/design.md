# Design

## Context

- `task-progress` introduces `TaskItem.remaining(sizes:)` from effort and recorded work, which all planning code uses. This change extends that function.
- Tables use sync columns and `Batch` (change log, undo per writer). `DerivedIndex` builds each item's search text when the item changes.
- The task page shows a field row and the notes; `TaskRow` shows chips under the title.

## Goals / Non-Goals

**Goals:**
- Parts are lightweight. They live inside their task and never act as tasks of their own.
- One remaining-effort function for all of planning.

**Non-Goals:**
- Parts with their own due dates, tags, notes or links, or parts nested in parts.
- Parts in the day view as separate rows.
- Recording work per part.

## Decisions

### S1: A parts table

Migration v8 adds `task_parts`, with sync columns plus `item_id`, `position` (REAL, so a part can move between two others without renumbering), `title` (non-empty), `effort` (nullable size) and `done_at` (nullable). `fetchTasks` loads parts per task, ordered by position, the same way as tags.

### S2: The remaining effort with parts

`remaining(sizes:)`: when any part has an effort, it returns the sum of `sizes[effort]` over the open parts with an effort. Otherwise it keeps the `task-progress` rule.
- The app hides "done for today" and the Remaining control when `hasEstimatedParts` is true.
- The task's own effort chip stays as the overall estimate. The rows show "2/5" and "<remaining> left".

### S3: Commands

`addPart`, `updatePart` (title, effort, done), `movePart` (new position), `deletePart` (soft delete), and `replaceParts` for MCP (diffs by id in one batch). All of them refresh the task's derived index.

### S4: Search

`DerivedIndex.refresh` for a task appends its part titles to the search text, so search finds the task. Results show the task, not the part.

### S5: Task page

A "Parts" section under the field row, with a checkbox, an editable title and an effort menu per part, a "+ Add part" field, delete in the context menu, and drag to reorder. When all parts are done and the task is open, a banner reads "All parts done" with a "Complete task" button.

### S6: MCP

The task shape gains `parts: [{id, title, effort, done}]`. `create_task` accepts `parts: [{title, effort?, done?}]`, and `update_task` accepts `parts` as described in the spec (S3 `replaceParts`). The tool descriptions explain that estimated parts drive the remaining effort.

## Risks / Trade-offs

- **[Parts estimates vs. task effort disagree]** E.g. XL as a task, but parts adding up to 1 day. → The parts win for planning, and the task page shows both ("XL · 1d left from parts"), so the difference is visible.
- **[Replacing the list over MCP]** An agent that forgets parts removes them. → The tool description says so, and undo restores them for the user.
