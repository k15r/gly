# Manual checks: subtasks

Build and run: `scripts/build.sh`, quit gly, restart its agent (Claude does `launchctl kickstart`), `open build/Build/Products/Debug/gly.app`.
Neutral test data only. Setup: Claude creates "Demo: plan offsite" (effort XL, due next Friday, tag `gly/checks/subtasks/demo`) without parts.

## A. Parts on the task page (task 2.1)

- [ ] A1 Open "Demo: plan offsite" → a "Parts" section with an "Add part" field; add "Outline", "Draft", "Review" (Return after each) → listed in that order, and the task's rows show "0/3" ("Break a task down").
- [ ] A2 Give them efforts S, L, S (menu at the right of each part) → the Progress row reads "1d 4h left from parts", "Set remaining…" and "Reset" are gone, and rows show "… left".
- [ ] A3 Tick off "Outline" → "1d 2h left from parts", rows show "1/3"; the day view plans with 1d 2h ("Ticking off a part").
- [ ] A4 Drag "Review" above "Draft" (or use Move Up in its context menu) → the order changes; ⌘Z moves it back.
- [ ] A5 Rename a part by editing its text (Return) → saved; delete a part from its context menu → gone, ⌘Z brings it back.
- [ ] A6 Tick off the remaining parts → "All parts done" with "Complete task"; the task stays open until you click it ("Last part ticked off").
- [ ] A7 With estimated parts, the task's rows in today's list don't offer "done for today".
- [ ] A8 Search (⌘K or the search field) for "Draft" → "Demo: plan offsite" is in the results ("Find by part").

## B. Agents (task 3.1)

- [ ] B1 Claude calls `create_task` with three parts (two estimated) → gly shows the parts in order, and the remaining effort is the sum of the two ("Agent breaks a task down").
- [ ] B2 Claude calls `update_task` with one part `done: true` → only that part is ticked off in gly ("Agent ticks off a part").
