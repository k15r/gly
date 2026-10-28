# Tasks

## 1. Core

- [x] 1.1 Work log (P1, P2): migration v7 `task_work`; `TaskItem.workedMinutes` loaded in `fetchTasks`, `remaining(sizes:)`; commands `recordWork`, `setRemaining`, `resetRemaining`, `undoTodaysPart`; verify with tests for "Effort changed later", "More left than thought", setting and resetting the remaining effort, undo of each command, and remaining never below zero
- [ ] 1.2 Planning uses remaining (P3): `plan`, `startBy`, `fits` on the remaining effort; verify with tests for "Day two of a big task", remaining 0 for a task due today, a forecast counting only recorded work, and the snooze check on the remaining effort

## 2. App

- [ ] 2.1 "Done for today" (P4) on today's planning rows, recorded state and take-back; remaining next to the effort chip; verify manually "Tick off today's part" and "Take it back"
- [ ] 2.2 Task page progress (P5): remaining in the field row, Progress section with history, Remaining control and Reset; verify manually "Set what's left" and "Reset"

## 3. Agents

- [ ] 3.1 MCP (P6): task shape, `update_task remaining_minutes`, `record_work`, descriptions; verify with MCP tests for "Agent records work" and "Agent sets what's left", attribution and one history step each

## 4. End to end

- [ ] 4.1 Write `docs/manual-checks-task-progress.md` (neutral test data), push it with `scripts/manual-checks.py push`; covers ticking off and taking back today's part, the next day's plan without "can't fit", setting and resetting the remaining effort, and an agent recording work; done when `pull` reports every check passed

## Workflow follow-up

- Apply after `future-day-planning` and `workweek` are archived; then `/opsx:verify task-progress` and archive.
