# Design

## Context

- `Planning` turns a task's effort into minutes with `sizes[effort]` in `plan`, `startBy` and `fits`. `TaskItem` carries `effort` and is built by `TaskQueries.fetchTasks`, which batch-loads tags per item.
- Tables use sync columns, and writes go through `Batch`, which records the change log, so undo per writer works for new tables too (as for `item_tags`).
- Planning rows are `TaskRow` with a `PlanNote`. The task page shows a field row (completion, priority, effort, due, status, tags).

## Goals / Non-Goals

**Goals:**
- One source of truth: the remaining effort follows from the effort and the recorded work alone.
- The click in the Today list costs nothing to undo.

**Non-Goals:**
- Time tracking (timers, start/stop).
- Recording work per part. That's `subtasks`, where parts take over.

## Decisions

### P1: A work log table

Migration v7 adds `task_work`, with sync columns plus `item_id`, `day` (YYYY-MM-DD), `minutes` (may be negative) and `kind` (`part` for "done for today", `adjust` for a set remaining effort, `agent` for `record_work`).
- Remaining = `max(0, sizes[effort] − sum(minutes))`.
- `fetchTasks` loads `workedMinutes` per task in one grouped query, like tags. `TaskItem.remaining(sizes:)` computes the rest.

**Alternative: a `remaining_minutes` column on items.** Rejected: it goes stale when the effort or the sizes change, it loses the per-day history, and "done for today" couldn't be taken back precisely.

### P2: Commands

- `recordWork(id:, day:, minutes:, kind:)` inserts a row.
- `setRemaining(id:, minutes:, day:)` inserts an `adjust` row of `(effort − worked) − minutes`.
- `resetRemaining(id:)` soft-deletes the task's work rows (restorable through undo).
- `undoTodaysPart(id:, day:)` soft-deletes that day's `part` row.

Each is one batch, so undo works per step.

### P3: Planning uses `remaining`

`Planning.plan`, `startBy` and `fits` take the effort minutes from `task.remaining(sizes:)`. A remaining effort of 0 behaves like "no work needed". The Today list keeps tasks that are due or overdue (needed 0) and drops the rest into Coming up, as for tasks with enough time.

### P4: "Done for today" in rows

`TaskRow` gets an optional action, shown on today's view for rows whose plan entry needs work today.
- **Not yet recorded:** the action records the plan's needed minutes as a `part` row for today.
- **Recorded:** the row shows "today's part done" with a check, and the action takes it back.
- The row usually moves from Today to Coming up afterwards, because nothing is needed today anymore. The mark travels with it, since it reads the work log for today.

### P5: Task page

The field row shows "XL · 1d 4h left". A "Progress" section lists the recorded work per day with signed amounts, has a "Remaining" control (days, hours, minutes, like the effort sizes) that writes an `adjust` row, and a "Reset" button.

### P6: MCP

- The task shape gains `remaining_minutes` and `worked_minutes` (null without effort).
- `update_task` accepts `remaining_minutes` (P2).
- The new tool `record_work {id, minutes, date?}` writes an `agent` row.
- The tool descriptions explain that planning uses the remaining effort.

## Risks / Trade-offs

- **[Negative adjustments]** Increasing the remaining effort writes negative work. → The history shows it as "+4h left (adjusted)", not as negative work.
- **[Effort sizes change]** Remaining efforts move with the size, since they're derived. → That's intended: sizes are the user's definition of effort.
- **[Overlap with forecasts]** A forecast counts recorded work only, never the future "done for today". → Consistent with the forecast assumption ("nothing done before that day").

## Migration Plan

Migration v7 creates the table, empty, and runs in the agent. Rollback means the older build ignores the table.
