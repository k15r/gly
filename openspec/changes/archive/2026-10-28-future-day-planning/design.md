# Design

## Context

- **Planning is already time-relative.** `Planning.plan(tasks, now:, …)` derives "today" from `now` and counts free time from `now`. `PlanningModel.freeMinutes(on:now:)` uses the whole working window for any day other than the real today. Only the day view pins planning to the real clock.
- **Day view:** `DayView.tasksSection` branches on `model.isToday`. Today gets `todaySections` (Today and Coming up); every other day gets a plain "Tasks due this day" list.
- **Queries:**
  - `TaskQueries.tasksForDay(day:today:)` includes overdue tasks only when `day == today`.
  - `TaskQueries.upcoming(today:horizon:)` takes its start day as a parameter, but `PlanningModel` observes it for the real today only.
  - `effectivelyOpenSQL` counts a snoozed task as open from its snooze date relative to the `:today` it gets, so queries for a later day already include tasks that are back by then.
- **Snooze transitions:** at midnight and on launch, the app sends `reconcileSnoozes(today:)`. It sets status `open` and **clears `snoozed_until`**, so nothing remembers the return day afterwards.
- **Snooze options** live in `TaskMenu` (`TaskViews.swift`): "Snooze until Tomorrow" / "Snooze 1 More Day", "Snooze until Next Monday" and "Snooze until…" (which opens the task). The menu is used in task rows and on the task page.
- **Calendar:** `CalendarModel.appointments(in:)` queries any range, with a single-entry cache.

## Goals / Non-Goals

**Goals:**
- Reuse the planning math unchanged. A later day is planning with a different start time, not a second algorithm.
- Each snooze cue has one clear data source.

**Non-Goals:**
- Tracking progress on tasks. The forecast assumes nothing is done before the viewed day, just as today's plan doesn't know about work already done.
- Planning views for past days.
- Exposing the return day through the MCP tools. It's a display aid; the task fields agents see stay as they are. (Agents do get the forecast itself, F7.)
- Sharing free time between tasks (unchanged from daily-planning).

## Decisions

### F1: Forecast = plan from the start of the viewed day

For a displayed day D ≥ today:
- `now` = the real clock when D is today, otherwise `D.interval().start`.
- Tasks = `tasksForDay(day: D, …)` with overdue included for D ≥ today and `isOverdue` relative to D, plus `upcoming(today: D, horizon:)`.
- Appointments = `calendars.appointments(in: horizonRange(today: D))`.

`Planning.plan` then yields the Today list, the work needed and Coming up for D without changes. `todaySections` becomes `planningSections(for: D)`. The title is "Today" or `DayView.title(for: D)`. Row reasons say "today ≥ …" or "<weekday> ≥ …".

- **Alternative: a separate forecast routine** that simulates days up to D. Rejected: it's more logic for a less honest result, since it would invent progress.

**Overdue tasks and "can't fit"** (found while checking): against the free time until the due date, every overdue task with an effort was "can't fit", because a past deadline leaves 0 minutes. On a later day with a free working day, that contradicted the header ("needs 2h · free 8h"). An overdue task is now judged against the free time left on the planned day: from now on for today, the whole day for a later day.

### F2: Upcoming is observed per displayed day

`PlanningModel` observes `upcoming(today: displayedDay, …)` and restarts the observation when the displayed day changes, the way `TasksModel` already restarts its day observation. Past days don't observe it.

### F3: The return day gets its own column

Migration v6 adds `items.snooze_ended_on` (YYYY-MM-DD):
- `reconcileSnoozes` sets it to the task's `snoozed_until` value (its scheduled return day) while clearing `snoozed_until`.
- Every user status change (snooze again, done, drop, reopen) clears it.

The "back from snooze" mark shows on displayed day D when:
- `snooze_ended_on == D` (the task is back and reconciled), or
- `status == snoozed && snoozed_until == D` (not reconciled yet, or a forecast of the return).

The tooltip's snooze date is the same value.

- **Alternative: keep `snoozed_until` after the task wakes.** Rejected: an open task with a snooze date reads as contradictory in code, in the history and in the MCP task data. Its meaning would depend on the status.
- **Alternative: derive the return day from the change log.** Rejected: it means querying history for a list row.
- **Consequence:** if the app wasn't running on the return day, the column holds the scheduled day. The mark then doesn't show on a later day, matching the spec ("on its snooze date").

### F4: The snooze cost in the task menu

`TaskMenu` gets a section header "Due <day> stays" above the snooze options when the task has a due date. For each dated option (Tomorrow / 1 More Day, Next Monday), when the task also has an effort, `PlanningModel.fits(task, returningOn:)` checks:

```
effort <= FreeTime.minutes(from: returnDay.start, to: deadline, busy: overrides.busy(appointments(returnDay ... deadline)))
```

If it doesn't fit, the option shows a warning symbol and "– won't fit anymore". A return day after the deadline gives 0 free minutes, so it always warns. "Snooze until…" has no date and shows no warning.

- macOS menus show no per-item tooltips, so the "due stays" information goes into the section header instead of a tooltip.
- **Alternative: show "start by" in the menu.** Rejected: it's another date to interpret, while a warning on the option itself answers the actual question.

### F5: Snoozed summary and popover

A new query `TaskQueries.snoozed(after: D)` returns tasks with status `snoozed` and `snoozed_until > D`, ordered by snooze date. `PlanningModel` observes it for the displayed day (D ≥ today). Under Coming up, a borderless button "N snoozed" opens a popover with rows of title, "until <day>" and due date; clicking a row closes the popover and navigates to the task. Tasks back on D aren't counted, because they already appear in D's lists.

### F7: `get_schedule` follows the day view

`get_schedule` shares `tasksForDay` with the day view and promises to match it (agent-access). For a date D ≥ today it therefore returns overdue tasks relative to D and the planning data (`today`, `coming_up`, `needed_today_minutes`, `without_estimate`). The plan comes from `Planning.plan` with `now` = the real clock for today and the start of D otherwise, and with `upcoming(today: D)`. Past dates keep their tasks and free time, without planning data. The tool description changes from "for today also" to "for today and later dates".

- **Alternative: keep agents on the old per-day list** with a separate query variant. Rejected: agents would see less than the user, which breaks the "matching the day view" promise.

### F6: Past days unchanged

D < today keeps the plain list. `tasksForDay` keeps its past-day behavior: due that day, no overdue, sorted by priority and due time.

## Risks / Trade-offs

- **[Calendar queries for menus]** Each fit check needs appointments up to the task's deadline, and the single-entry range cache in `CalendarModel` would keep evicting itself between rows. → Compute the check when the menu is built, only for tasks with both due date and effort. Give `CalendarModel` a small cache keyed by range (a few entries, cleared on calendar changes).
- **[The forecast reads as a promise]** Overdue tasks on a later day could alarm. → It's labeled with the date, and the overdue reason makes the cause obvious. This was the explicit choice ("from that day's perspective").
- **[Midnight]** When D becomes today, the plan switches from the whole working day to "from now". → That's existing behavior through `clock.today`; no special handling.
- **[Migration]** v6 adds a nullable column. Existing rows are untouched; the change log records the new field like any other.

## Migration Plan

Schema migration v6 runs in the agent on start, like v1–v5. No data backfill: tasks already back from a snooze before the update just won't show the mark that day. Rollback means the older build ignores the extra column.
