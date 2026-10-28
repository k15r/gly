# Tasks

## 1. Core

- [ ] 1.1 Parts (S1, S3, S4): migration v8 `task_parts`; `TaskItem.parts`; commands `addPart`, `updatePart`, `movePart`, `deletePart`, `replaceParts`; part titles in the task's search text; verify with tests for "Break a task down" (order, counts), moving between two parts, undo of each command, `replaceParts` keeping/adding/removing by id, and "Find by part"
- [ ] 1.2 Remaining from parts (S2): `remaining(sizes:)` with estimated parts; verify with tests for "Ticking off a part", "Unestimated parts", and planning using the parts' sum

## 2. App

- [ ] 2.1 Task page Parts section and "All parts done" banner (S5); "2/5" in rows; hide "done for today" and the Remaining control with estimated parts; verify manually "Break a task down", "All parts done", "Ticking off a part"

## 3. Agents

- [ ] 3.1 MCP (S6): parts in the task shape, `create_task` and `update_task` parts; verify with MCP tests for "Agent breaks a task down" and "Agent ticks off a part"

## 4. End to end

- [ ] 4.1 Write `docs/manual-checks-subtasks.md` (neutral test data), push it with `scripts/manual-checks.py push`; covers breaking a task down, ticking off parts and the plan following, reordering, the complete prompt, search by part and an agent adding parts; done when `pull` reports every check passed

## Workflow follow-up

- Apply after `task-progress` is archived; then `/opsx:verify subtasks` and archive.
