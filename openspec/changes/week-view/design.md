# Design

## Context

- `Planning.plan(tasks, now:, …)` computes a day's Today list, needed minutes and Coming up. A later day is planned from its start (future-day-planning F1).
- The day's tasks come from `TaskQueries.tasksForDay(day:today:)` and `upcoming(today:horizon:)`, observed for the displayed day by `TasksModel` and `PlanningModel`.
- Free time per day is `PlanningModel.freeMinutes(on:now:appointments:)`, which honors the working days.

## Goals / Non-Goals

**Goals:**
- The strip's numbers match each day's header exactly: same function, same inputs.

**Non-Goals:**
- A full week page or week planning interactions such as dragging tasks between days.
- An MCP tool for the week.

## Decisions

### W1: `Planning.week`

`Planning.week(days: [LocalDay], tasks: [TaskItem], today:, now:, sizes:, hours:, busy:) -> [DayLoad]`, where `DayLoad` holds day, needed minutes, free minutes and isPast. For each day from today on, it runs `Planning.plan` on the open tasks relevant to that day: due up to that day, plus those due within the horizon after it, skipping tasks snoozed past it. `now` is the real clock for today and the start of the day otherwise. Free time comes from `FreeTime.minutes` over that day's working window. It reuses the existing plan, so the numbers can't drift from the header.

### W2: Data

`PlanningModel` observes one query for the week: the open tasks due up to the week's last day plus the horizon, with their tags, work and notes for parts. Appointments for the week come from `calendars.appointments(in:)`, which the range cache added in future-day-planning covers.

### W3: `WeekStrip`

An `HStack` of equal-width capsules for the working days (`hours.workdays`, in the week's order):
- **Today and later:** a weekday label and "needed / free", with a thin fill bar showing needed against free, in orange with a warning icon when short.
- **Past days:** dimmed, with only the label.
- **The displayed day:** marked with the accent color.

Clicking an entry sets `nav.day`. It uses the status palette from `status-colors`.

## Risks / Trade-offs

- **[Cost]** Five plans per refresh. → Each is a pass over a few dozen tasks; it runs only when the observed data, the clock's day or the displayed week changes.
