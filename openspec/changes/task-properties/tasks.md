# Tasks

## 1. Core

- [ ] 1.1 `DateWords` (T3): day words and an optional trailing time as a public parser, used by `CaptureParser`; verify with tests for weekdays, "today"/"tomorrow", "3 nov", "fri 14:00", nonsense → nil, and the existing capture tests unchanged

## 2. App

- [ ] 2.1 `PropertyChip` and the chip row (T1, T4): priority, effort, due, snooze, tags; empty chips faded with "+"; status picker removed (Reopen/Drop in the ⋯ menu); verify manually "Empty properties"
- [ ] 2.2 Popovers (T2): priority with 0–4 keys, effort with sizes and "Set remaining…", due with quick picks, text field, calendar, time and remove, snooze with warnings and "Wake now"; verify manually "Set a due date by typing", "Snooze from the chip", "Set effort on the task page", undo of each
- [ ] 2.3 Tag chips on pages and meeting pages (T5); verify manually

## 3. End to end

- [ ] 3.1 Write `docs/manual-checks-task-properties.md` (neutral test data), push it with `scripts/manual-checks.py push`; covers every chip and popover, typed dates incl. time, snooze warnings and wake, tags on all three page kinds, and undo; done when `pull` reports every check passed

## Workflow follow-up

- Apply after `live-preview` is archived; then `/opsx:verify task-properties` and archive.
