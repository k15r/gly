# Proposal

## Why

The Today and Coming up sections only exist on today's view. Looking at a later day shows a plain list of tasks due that day, so I can't see what that day will demand: which tasks will be overdue by then, what needs work that day to stay on track, and whether it fits. Snoozing makes this worse: a snoozed task vanishes and comes back without a word, often with much less time left, and nothing tells me what a snooze costs before I choose it.

## What Changes

- **Planning for future days:** a future day's view shows the same Today and Coming up sections, seen from that day: its whole working time counts as free, tasks still open from earlier days count as overdue, and Coming up covers the N days after it. It is a forecast that assumes nothing gets done before then.
- **Labels:** on a future day the section is titled with the date (e.g. "Thu 29 Oct") instead of "Today", and the empty text says "that day".
- **Past days** keep the plain list of tasks due that day.
- **Back from snooze:** on the day a snoozed task comes back (today, or a future day in the forecast), its row is marked "back from snooze", with a tooltip naming the snooze date and that the due date did not change.
- **What a snooze costs:** the snooze options in a task's menu show that the due date stays, and warn when the task would no longer fit after coming back.
- **Snoozed tasks stay findable:** under Coming up, a line "N snoozed" opens a list of the tasks still snoozed on the displayed day, with their return and due dates.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `day-view`: tasks for future days are shown as the planning sections instead of a plain list; the snooze behavior on future days changes accordingly.
- `daily-planning`: the Today list, the work needed, its header and Coming up apply to today and future days; adds the "back from snooze" mark and the snoozed-tasks summary.
- `tasks`: snoozing shows that the due date stays and warns when the task would no longer fit.

## Impact

- `Apps/Mac/App/DayView.swift`: planning sections for future days, labels, back-from-snooze mark, snoozed summary and its popover.
- `Apps/Mac/App/TaskViews.swift`: snooze options in the task menu with the due date and the fit warning.
- `Apps/Mac/App/PlanningModel.swift`, `TasksModel.swift`: plan from the start of the displayed day; data for the snoozed summary.
- `GlyCore`: `TaskQueries` (overdue from the displayed day's view, snoozed tasks), the day a task came back from a snooze (stored with the task; schema migration v6), `Planning` unchanged except for a fit check.
- No change to the MCP tools.
