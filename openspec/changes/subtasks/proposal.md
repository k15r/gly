# Proposal

## Why

Large tasks are several steps, and "XL, 2 days left" says nothing about which steps. A checklist of parts, each with its own small effort, shows what's left and gives a natural progress signal: ticking off a part reduces what the plan still expects.

## What Changes

- **Parts:** a task can have parts. Each is a checklist item with a title, an optional effort (`XS`–`XL`) and a done mark. On the task page they can be added, renamed, estimated, ticked off, reordered and deleted.
- **Parts drive the remaining effort:** when at least one part has an effort, the task's remaining effort is the sum of its open parts' efforts. "Done for today" and setting the remaining effort by hand (from `task-progress`) apply only to tasks without such parts.
- **Rows** show progress as "2/5", and the task page offers to complete the task once all parts are done (no automatic completion).
- **Search** finds a task by the titles of its parts.
- **Agents** see the parts and can create, change and tick them off.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `tasks`: adds parts of a task.
- `daily-planning`: the remaining effort comes from the parts when they're estimated.
- `agent-access`: parts over MCP.

## Impact

- `GlyCore`: new table `task_parts` (migration v8, synced, in the history), part commands, `TaskItem.parts`, `remaining` from parts, part titles in the task's search text.
- App: task page checklist, "2/5" in rows, the complete-when-done prompt, hiding "done for today" and the remaining control for tasks with estimated parts.
- `GlyMCP`: `parts` in the task shape, `create_task` and `update_task`.
- Builds on `task-progress` (remaining effort); apply after it.
