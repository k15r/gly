# Proposal

## Why

Large tasks are several steps, and "XL, 2 days left" says nothing about which steps. The notes can already hold a checklist (`- [ ]` / `- [x]`, clickable in the editor and the read view). Those checklist items should be the task's parts: with an estimate per item, ticking one off reduces what the plan still expects, without a second editing model.

## What Changes

- **Parts are the checklist items of a task's notes**, in their order in the text. An item may end with an estimate in parentheses: a size `(XS)`…`(XL)` or a duration such as `(30m)`, `(2h)`, `(1d)` or `(1d 4h)`, where a day is a working day.
- **Estimated parts drive the remaining effort:** when at least one item has an estimate, the remaining effort is the sum of the open items' estimates. "Done for today" and setting the remaining effort by hand (from `task-progress`) apply only to tasks without estimated items.
- **Progress shows everywhere:** rows show "2/5" and "… left", and the task page offers to complete the task once all items are ticked off (no automatic completion).
- **Agents** see the parts in the task data, read-only. They change them by editing the notes, as before.
- Writing, ticking off, reordering, undo and search work as they do for the notes today.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `tasks`: the checklist items of the notes are the task's parts, with optional estimates; prompt when all are done.
- `daily-planning`: the remaining effort comes from the estimated parts.
- `agent-access`: parts in the task data.

## Impact

- `GlyCore`: a parser for checklist items with estimates (outside code blocks), `TaskItem.parts` derived from the notes, the remaining effort from estimated parts (needs the working-day length for durations).
- App: "2/5" and "… left" in rows, the Progress row ("… left from parts"), the "All parts done" banner, no "done for today" or manual remaining for such tasks.
- `GlyMCP`: `parts` in the task shape, read-only; tool descriptions explain the syntax.
- A first version built a separate parts table (migration v8). It is replaced. The migration stays, because migrations are additive; the table is left empty.
- Builds on `task-progress`.
