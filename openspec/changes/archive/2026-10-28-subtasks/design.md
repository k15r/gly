# Design

## Context

- **Notes checklists already work:** `- [ ]` / `- [x]` lines are styled as checkboxes in the editor and toggle by click in both the editor and the read view (`MarkdownBlocks.toggleChecklist`, specs/markdown-editing "Checklists"). Changes are notes edits: one undo step per edit session, searchable, writable by agents through `update_task notes`.
- **Remaining effort:** `task-progress` introduced `TaskItem.remaining(sizes:)` (effort minus recorded work), which all planning code uses.
- **A first version** of this change built a separate parts table with its own commands and UI (migration v8). This design replaces it.

## Goals / Non-Goals

**Goals:**
- One editing model: parts are text. No separate list, commands or controls.
- Parts and their estimates are derived when tasks are read; nothing is stored beyond the notes.

**Non-Goals:**
- Links or tags per part, or nested parts counted separately (an indented item is just another part).
- Recording work per part.
- Writing parts through dedicated MCP parameters.

## Decisions

### S1: Parsing (`ChecklistParts`)

GlyCore parses the notes line by line, skipping fenced code blocks (the same fence rule as the styler).
- **Items:** a line matching `^[ \t]*[-*+][ \t]+\[( |x|X)\][ \t]+(.*)$` is a part. Its title is the rest of the line, without a trailing estimate.
- **Estimate:** a trailing `(<estimate>)`:
  - a size: `XS|S|M|L|XL`, case-sensitive
  - or a duration: `(\d+d)?\s*(\d+h)?\s*(\d+m)?` with at least one unit, lower case
  - anything else in parentheses stays part of the title
- **Model:** `TaskPart { title, estimate: PartEstimate?, done }`, where `PartEstimate` is `.size(Effort)` or `.duration(days:minutes:)`.
- `TaskItem.parts` is a computed property over `body`, so every task read carries it with no extra query.

### S2: The remaining effort with parts

`remaining(sizes:dayMinutes:)`: with any estimated part, the result is the sum over the open estimated parts. A size uses `sizes[effort]`; a duration is `days × dayMinutes + minutes`. Otherwise the `task-progress` rule applies.
- `dayMinutes` is the working-day length (`WorkingHours.minutesPerDay`). Planning, the MCP encoder and the app pass it.
- The app hides "done for today" and the remaining control while `hasEstimatedParts` is true.

### S3: The first version's parts table

The part commands, `PartPatch`, `PartInput`, the parts in `TaskDraft` and `TaskPatch`, the part undo labels and the derived-index hook are removed. Migration v8 stays registered (migrations are only added) and its table stays empty and unused. It's dropped from `Schema.syncedTables`, so it's never synced.

### S4: App

- Rows show "done/total" when a task has parts, and "… left" when the parts drive the remaining effort.
- On the task page, the Progress row reads "… left from parts" (plus "N without estimate"), and an "All parts done" banner with "Complete task" appears while the task is open.
- Editing parts is editing the notes.

### S5: MCP

The task shape has `parts: [{title, estimate_minutes, done}]` (read-only). The `create_task`/`update_task` notes descriptions explain `- [ ] Title (S)` / `(2h)`, and that estimated items drive the remaining effort.

## Risks / Trade-offs

- **[Every checklist in task notes counts]** A to-do list written for another purpose becomes parts. → That's intended. Parts only drive planning once an item has an estimate.
- **[Estimate syntax in the title text]** "Call (2h)" reads as an estimate. → Only a trailing, exactly matching parenthesis counts; anything else stays in the title.
- **[Durations depend on the working day]** "(1d)" changes when the working hours change. → That's consistent with the effort sizes, which do the same.
