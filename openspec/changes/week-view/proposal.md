# Proposal

## Why

With the forecast for later days, working days and remaining efforts, gly can tell for any day how much work it needs and how much time it has. But that only shows one day at a time. "Can I take on another task this week?" means clicking through five days.

## What Changes

- **A week strip** at the top of the day view: one small bar per working day of the displayed day's week, showing the work needed against the free time (e.g. "6h / 7h"). A day that's short is marked in the warning color.
- **Clicking a day** in the strip opens it. The displayed day is highlighted, and past days are dimmed without numbers.
- The numbers are the same as each day's planning header (needs · free), from the same forecast.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `daily-planning`: adds the week overview.

## Impact

- `GlyCore`: `Planning.week(...)` computes needed and free minutes per working day from the existing plan (tasks due up to each day plus the horizon).
- App: a `WeekStrip` view above the day view; `PlanningModel` observes the tasks needed for the week.
- `GlyMCP`: optional later; not part of this change.
