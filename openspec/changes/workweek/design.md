# Design

## Context

- `WorkingHours` (start and end minute) gives every day the same window (`window(on:)`). `FreeTime.minutes` sums the window minus appointments over each day in a range.
- Everything that plans counts free time through `FreeTime`: the work needed, "can't fit", `startBy`, `Planning.fits` (the snooze warning), the day header, the capacity bar and `get_schedule`.
- `SharedSettings.workingHours` is read by the app and by the agent (for `get_schedule`).

## Goals / Non-Goals

**Goals:**
- One rule in one place: a non-working day has no working window. Every consumer follows without changes of its own.

**Non-Goals:**
- Holidays, days off, and different hours per weekday.
- Changing the effort sizes, which stay defined in working days.

## Decisions

### W1: Working days are part of `WorkingHours`

`WorkingHours.workdays: Set<Int>` holds `Calendar` weekday numbers (1 = Sunday … 7 = Saturday), default 2…6. `window(on:)` returns nil when the day's weekday isn't in the set, so `FreeTime.minutes` counts nothing there.

- **Alternative: a separate parameter on `FreeTime` and every caller.** Rejected: it means threading a new value through all callers, and it's easy to miss one, such as the snooze check or the MCP planning data.

### W2: "Start by" needs no change

`startBy` walks back from the due day and returns the latest day from which the free time until the deadline is enough. A non-working day adds no time, so its result equals that of the next working day, which the walk reaches first. The result is never a non-working day. A test pins this down.

### W3: Stored as `workingDays` in the shared settings

The days are an array of weekday numbers under `workingDays` in the app-group defaults. Missing or empty means Monday to Friday. The app and the agent pick it up through `workingHours`, as they do for the hours.

### W4: Settings UI

Settings → Planning → Working hours gets a row of seven weekday toggles, in the locale's week order (`Calendar.firstWeekday`) with short names. At least one day must stay selected. The caption changes from "The same every day" to "On the selected days".

## Risks / Trade-offs

- **[Planning on a non-working day's view]** Saturday's forecast shows "free 0m", and tasks that need work then appear as short. → That's the honest answer ("this should have been done by Friday"), and it follows from the rule without special cases.
- **[Existing settings]** Users so far had seven working days. → The default switches to Monday–Friday, which is the intended fix.
