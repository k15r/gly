# Manual checks: status-colors

Build and run: `scripts/build.sh`, quit gly, `open build/Build/Products/Debug/gly.app`.
Neutral test data only. Setup: Claude creates demo tasks tagged `gly/checks/status-colors/demo`: one due yesterday (effort M), one due today, one due in 3 days with effort XL (so it needs work today), one snoozed until today.

## A. Rows (task 2.1)

- [ ] A1 The task due yesterday shows a red bar on the left; its tooltip says "Overdue since yesterday"; chips show "M" and yesterday's date in red ("Overdue task row").
- [ ] A2 The task due today has an orange bar and "due" with an icon next to the title; the XL task a blue bar and "today ≥ …"; the snoozed task (back today) a purple bar ("Not by color alone").
- [ ] A3 The same tasks look the same in the day view, the task list, the tag page of the demo tag, and search (⌘K: task hits have the bar) ("Same meaning everywhere").
- [ ] A4 Hover a row → snooze, effort and open buttons appear; snooze opens the same popover as the task page's snooze chip ("Quick action"); effort opens the effort list.
- [ ] A5 Right-click a row → Priority, Effort, snooze options, Drop, Delete are there; the old priority menu at the right is gone.
- [ ] A6 Appointments show their calendar color as a slim bar, aligned with the task rows' bars.
- [ ] A7 Completing a task: the circle turns green; done tasks in the task list's Done view show a green bar.
