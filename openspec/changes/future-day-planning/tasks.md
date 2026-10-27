# Tasks

## 1. Core

- [x] 1.1 Overdue from the displayed day (F1, F6): `tasksForDay` includes overdue tasks for any day ≥ today with `isOverdue` relative to that day, past days unchanged; verify with tests for "Future day" (a task due today and still open is overdue on tomorrow's list), "Past day" and "Snoozed until tomorrow" (absent today, present tomorrow), plus a `Planning.plan` test for "Forecast for a later day" (`now` = start of Wednesday gives "≥ 1 day")
- [ ] 1.2 Return day (F3): migration v6 adds `items.snooze_ended_on`; `reconcileSnoozes` sets it from `snoozed_until`, user status changes clear it; add a helper telling whether a task is back from snooze on a given day (reconciled or still snoozed until that day); verify with schema and command tests (set on reconcile, cleared on snooze/done/drop/reopen, undo restores it) and helper tests for today, a forecast day and the day after
- [ ] 1.3 Snoozed query (F5): `TaskQueries.snoozed(after:)` returns tasks still snoozed after a day, ordered by snooze date; verify with tests for "See snoozed tasks" and "Snoozed until the viewed day" (not counted on its return day)
- [x] 1.4 `get_schedule` forecast (F7): overdue tasks and planning data (`today`, `coming_up`, needed minutes) for any date ≥ today, planned from the start of a later date, past dates without planning data; tool description updated; verify with MCP tests for "Another day", "Past day" and "Planning data for a later day"

## 2. Day view

- [ ] 2.1 Planning sections for D ≥ today (F1, F2): `PlanningModel` observes `upcoming` for the displayed day and plans from the start of a later day; `todaySections` becomes `planningSections(for:)` with the date title, "that day" empty text and weekday reasons; past days keep the plain list; verify with a clean build and manually "Forecast for a later day", "Horizon from a later day", "Future day", "Past day"
- [ ] 2.2 Back-from-snooze mark (F3): moon icon and "back from snooze" on Today and Coming up rows when the helper says so, tooltip "Snoozed until <day> – due <day> unchanged"; verify manually "Back today" and "Forecast of the return"
- [ ] 2.3 Snoozed summary (F5): "N snoozed" under Coming up for D ≥ today, popover with title, "until <day>" and due date, click opens the task; verify manually "See snoozed tasks"

## 3. Snooze menu

- [ ] 3.1 Snooze cost (F4): `PlanningModel.fits(_:returningOn:)` and a small range-keyed appointment cache in `CalendarModel`; `TaskMenu` shows the "Due <day> stays" section header and the "won't fit anymore" warning on dated snooze options; verify with a `fits` test (fits tomorrow, not next Monday, after the deadline never) and manually "Snooze too long" and "No estimate"

## 4. End to end

- [ ] 4.1 Write `docs/manual-checks-future-day-planning.md` (neutral test data) and push it as gly tasks with `scripts/manual-checks.py push`; covers the forecast on tomorrow and a later day, overdue from that day, the past-day list, snoozing with and without the warning, the back-from-snooze mark today and in the forecast, the snoozed popover, and midnight turning a forecast into today's plan; done when `pull` reports every check passed

## Workflow follow-up

- Run `/opsx:verify future-day-planning`, then archive after the manual checks pass.
