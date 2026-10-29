# Tasks

## 1. Palette

- [x] 1.1 `StatusColor` (C1) and `rowStatus` (C2) with tooltip texts; `PlanNote` uses the palette; verify with tests for the status order (can't fit > overdue > due > needs work > back from snooze) and the tooltip texts

## 2. Rows

- [ ] 2.1 `TaskRow` rebuilt (C3): status bar, compact chips, hover quick actions, priority symbol, no priority menu; appointment bars aligned (C4); verify manually "Overdue task row", "Quick action", "Same meaning everywhere", "Not by color alone" in the day view, task list, tag page and search

## 3. End to end

- [ ] 3.1 Write `docs/manual-checks-status-colors.md` (neutral test data), push it with `scripts/manual-checks.py push`; done when `pull` reports every check passed

## Workflow follow-up

- `/opsx:verify status-colors` and archive, then `readability`.
