# Proposal

## Why

The plan doesn't know about progress. A task with effort `XL` counts as three untouched working days until it's completed. After a full day of work on it, the next day says "can't fit" in orange, although I'm on track. Forecasts of later days have the same blind spot.

## What Changes

- **Remaining effort:** a task with an effort has a remaining effort: its effort minus the work recorded on it. Planning uses the remaining effort wherever it used the effort: work needed, "can't fit", start by, forecasts, the snooze warning and the agents' planning data.
- **"Done for today":** a planning row that asks for work today can be ticked off. That records the amount asked for as worked today. Clicking again takes it back.
- **Remaining effort by hand:** the task page shows the remaining effort and the recorded work per day, and lets me set the remaining effort directly ("1d 4h left") or reset it to the full effort.
- Rows of tasks with recorded work show what's left next to the effort chip (e.g. "XL · 2d left").
- **Agents** see the remaining and worked minutes, can set the remaining effort, and can record work.

Subtasks follow in their own change (`subtasks`), which computes the remaining effort from parts.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `tasks`: adds remaining effort, recorded work and editing them on the task page.
- `daily-planning`: planning uses the remaining effort; planning rows can record today's part.
- `agent-access`: progress over MCP.

## Impact

- `GlyCore`: new table `task_work` (migration v7, synced and in the history like other tables), commands to record work and set the remaining effort, `TaskItem` carries the worked minutes, `Planning` uses the remaining effort.
- App: planning rows (done-for-today button, remaining next to the chip), task page (remaining effort and history).
- `GlyMCP`: task shape gains `remaining_minutes` and `worked_minutes`; `update_task` accepts `remaining_minutes`; new tool `record_work`.
- Builds on `future-day-planning` and `workweek` (planning code and specs); apply after both.
