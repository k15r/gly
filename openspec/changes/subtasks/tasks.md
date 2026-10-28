# Tasks

## 1. Core

- [x] 1.1 Parts from the notes (S1, S3): `ChecklistParts` parser (items outside code blocks, sizes and durations as estimates, titles without them), `TaskItem.parts` derived from the notes; remove the first version's part table code (commands, patches, drafts, labels, index hook) and drop `task_parts` from `syncedTables`; verify with tests for "Break a task down", "Item without estimate", code blocks ignored, non-estimate parentheses kept in the title, and the size/duration forms
- [x] 1.2 Remaining from parts (S2): `remaining(sizes:dayMinutes:)` at all call sites; verify with tests for "Ticking off a part", "Unestimated parts", durations following the working day, and planning using the parts' sum

## 2. App

- [x] 2.1 Rows "2/5" and "… left", Progress row "… left from parts", "All parts done" banner, hide "done for today" and the Remaining control with estimated parts; remove the Parts section (S4); verify manually "Break a task down", "Last part ticked off", "Ticking off a part"

## 3. Agents

- [x] 3.1 MCP (S5): read-only `parts` in the task shape, no part parameters, descriptions of the syntax; verify with MCP tests for "Agent breaks a task down" and "Agent ticks off a part"

## 4. End to end

- [x] 4.1 Rewrite `docs/manual-checks-subtasks.md` for checklist parts (neutral test data), push it with `scripts/manual-checks.py push`; covers writing items with sizes and durations, ticking them off and the plan following, the complete prompt, and an agent changing a part via the notes; done when `pull` reports every check passed

## Workflow follow-up

- `/opsx:verify subtasks` and archive.
