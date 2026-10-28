# Manual checks: future-day-planning

Build and run: `scripts/build.sh`, quit gly, restart its agent (Claude does `launchctl kickstart`), `open build/Build/Products/Debug/gly.app`.
Neutral test data only (no real names). Setup (Claude creates these, tagged `gly/checks/future-day-planning/demo`; delete them afterwards):
- "Demo: call venue" – due today, effort S
- "Demo: write report" – due this Friday, effort XL
- "Demo: no estimate" – due this Friday, no effort
- "Demo: no due date" – no due date, effort S

## A. Planning on later days (task 2.1)

- [x] A1 Go to tomorrow → the planning section is titled with tomorrow's date (e.g. "Wed 28 Oct"), its header shows the whole working day as free (minus meetings), and "Demo: call venue" is listed marked "overdue" ("Future day").
- [x] A2 "Demo: write report" (3 days, due Friday) shows a weekday note on Wednesday, e.g. "Wed ≥ 1d" (more if Thursday/Friday have meetings), and "can't fit" on Thursday ("Forecast for a later day").
- [x] A3 On a later day, Coming up lists tasks due up to N days after that day, not after today ("Horizon from a later day").
- [x] A4 Go to yesterday → the plain "Tasks due this day" list, no overdue tasks, no Today/Coming up ("Past day").
- [x] A5 A later day with nothing to do says "Nothing needs work that day".
- [x] A6 On a later day with free time, "Demo: call venue" (2h, overdue) shows "overdue" but not "can't fit"; it says "can't fit" only on a day with less than 2h free ("Overdue but fits the day").

## B. Snoozing (tasks 2.2, 2.3)

- [x] B1 Snooze "Demo: call venue" until tomorrow → it's gone from today, and "1 snoozed" appears under Coming up ("Snoozed until tomorrow").
- [x] B2 Go to tomorrow → it's listed marked "overdue" and "back from snooze"; the tooltip says "Snoozed until … – due … unchanged"; the day after shows no mark ("Forecast of the return").
- [x] B3 Click "N snoozed" → a list with "until <day>" and the due date, earliest return first; clicking a task opens it ("See snoozed tasks").
- [x] B4 On tomorrow's view the task snoozed until tomorrow is not counted in "N snoozed" ("Snoozed until the viewed day").
- [x] B5 Claude snoozes a demo task until today over MCP → today's list shows it with "back from snooze" ("Back today").

## C. Snooze menu (task 3.1)

- [x] C1 Right-click "Demo: write report" → the snooze options sit under "Due <Fri date> stays"; "Snooze until Tomorrow" has no warning; "Snooze until Next Monday" shows "– won't fit anymore" with a warning symbol ("Snooze too long").
- [x] C2 Right-click "Demo: no estimate" → the "Due … stays" heading, no warnings ("No estimate").
- [x] C3 Right-click "Demo: no due date" → no heading, no warnings.

## D. Agents and the next day

- [x] D1 Claude calls `get_schedule` for tomorrow → the overdue demo task, `today` and `coming_up` for tomorrow, free time of the whole day.
- [x] D2 Next day: tomorrow's forecast has become today's plan (free time from now on, title "Today").
