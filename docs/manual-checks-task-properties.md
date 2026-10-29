# Manual checks: task-properties

Build and run: `scripts/build.sh`, quit gly, `open build/Build/Products/Debug/gly.app`.
Neutral test data only. Setup: "Demo: properties" (no priority, effort, due date or tags; tag added in A6) exists.

## A. Chips and popovers (tasks 2.1, 2.2)

- [x] A1 Open "Demo: properties" → under the title a row of faded chips "+ Priority", "+ Effort", "+ Due", "+ Snooze", "+ Tag"; no Priority/Effort/Status pickers ("Empty properties").
- [x] A2 Priority chip → popover Urgent … None; press 3 → High is set, the chip shows it, the popover closes; ⌘Z undoes it.
- [x] A3 Effort chip → pick M → chip "M"; with an effort, the popover also offers the remaining stepper ("Set effort on the task page").
- [x] A4 Due chip → pick a Friday in the calendar → the chip reads e.g. "Fri 30. Oct"; ⌘Z undoes it ("Set a due date in the calendar").
- [x] A5 Due chip → quick picks, the calendar, "Add time" / time field / "Remove time", and "Remove" all work; an overdue date shows the chip in red.
- [x] A6 Snooze chip → same layout as the due popover: "Due … stays", quick picks (orange with a warning when it won't fit) and a calendar → pick Monday → chip "Snoozed until Mon"; reopen → "Wake now" makes it open again ("Snooze from the chip").
- [x] A7 The ⋯ menu still has Drop and (for done/dropped tasks) Reopen.

## B. Tags everywhere (task 2.3)

- [x] B1 On the task, a page and a meeting page: tags are chips, ✕ appears on hover and removes the tag, "+ Tag" adds one (incl. "New tag…").
