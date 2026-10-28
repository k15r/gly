# Manual checks: task-progress

Build and run: `scripts/build.sh`, quit gly, restart its agent (Claude does `launchctl kickstart`), `open build/Build/Products/Debug/gly.app`.
Neutral test data only. Setup: "Demo: write report" (XL, due Tue 3 Nov) from the earlier demo tasks; if it's not in today's list with "today ≥ …", Claude moves its due date so it is.

## A. Done for today (task 2.1)

- [ ] A1 In today's list, "Demo: write report" shows "today ≥ …" and a "done for today" button; click it → the row shows "today's part done" (green), the task's effort chip is followed by "… left", and it moves to Coming up if nothing more is needed today ("Tick off today's part").
- [ ] A2 Click "today's part done" again → it's taken back: "today ≥ …" returns and "… left" disappears ("Take it back").
- [ ] A3 Tick it off again, then ⌘Z → the undo label reads "Undo Record work on “Demo: write report”" and undoes it.
- [ ] A4 Forecast: tick it off, then view tomorrow → the report is planned with what's left (no "can't fit" because of the part already done).
- [ ] A5 Next day: the report shows "today ≥ …" for the remaining work, not "can't fit" ("Day two of a big task").

## B. Task page (task 2.2)

- [ ] B1 Open "Demo: write report" → a "Progress" row under the fields shows what's left and the recorded days (e.g. "Wed 1d").
- [ ] B2 "Set remaining…" → step to 1d 4h → Set → the page and its rows show "1d 4h left"; the Progress row lists today's adjustment ("Set what's left").
- [ ] B3 Set it higher than what's left before → the history shows "+… left (adjusted)" ("More left than thought").
- [ ] B4 "Reset" → back to the full effort, history gone; ⌘Z brings it back ("Reset").
- [ ] B5 A task without effort shows no Progress row.

## C. Agents (task 3.1)

- [ ] C1 Claude calls `record_work` (2h) on "Demo: write report" → gly shows 2h less left, and the history lists it "by an agent" ("Agent records work").
- [ ] C2 Claude calls `update_task` with `remaining_minutes` → gly shows that remaining effort ("Agent sets what's left").
