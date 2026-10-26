# Manual checks: planning-day-view

Build and run: `scripts/build.sh && open build/Build/Products/Debug/WorkDash.app`.
Neutral test data only (no real names).

## A. Probe (task 1.1)

- [x] A1 Developer → Probe Attendance Data → a message with the file path appears (the file holds only counts per account type).

## B. Settings and effort (tasks 5.1, 5.2)

- [x] B1 Settings (⌘,) → Planning: working hours 09:00–17:00, sizes XS 30m, S 2h, M 4h, L 8h, XL 24h, look-ahead 5 days.
- [x] B2 Change working hours to 08:00–16:00 → the day view's "free …" changes at once; L and XL follow the shorter day; "Default" resets a size.
- [ ] B3 Right-click a task → Effort → M → an `M` chip appears on the row; ⌘Z removes it ("Effort of …").
- [ ] B4 On a task page, the Effort picker sets and clears the effort; one ⌘Z per change.

## C. Day view (task 5.3)

- [ ] C1 The header shows "free Xh Ym" and a bar; on a busy day the bar is short. Viewing tomorrow shows tomorrow's free time.
- [ ] C2 "Work on" lists open tasks due in the next 5 days, sorted late → tight → start today → ok → no estimate; the picker switches to 3/7/14 days and the choice is kept.
- [ ] C3 Hover a "Work on" row → tooltip "Needs ~…, free until due: …". Tasks due today show a state badge too.
- [ ] C4 Decline a meeting in Outlook (or Apple Calendar) → once it reaches the calendar, free time and states update by themselves.

## D. Appointment overrides (task 5.4)

- [ ] D1 Each appointment row has a small circle (filled = blocks, half = maybe, empty = free). Its tooltip says why ("automatic" or "set for …").
- [ ] D2 Circle menu → This occurrence → Ignore → the circle turns empty/accented, free time grows; the next week's occurrence still blocks. ⌘Z undoes it.
- [ ] D3 On a recurring meeting: Whole series → Optional → every occurrence counts half; a single occurrence set to Blocks overrides the series. Non-recurring meetings don't offer "Whole series".
- [ ] D4 Automatic → back to the calendar's classification.

## E. End to end (task 6.1)

- [ ] E1 A real week with Exchange meetings: ignore one occurrence and make one series optional; check free time per day looks right.
- [ ] E2 Move an overridden meeting in Outlook → after it syncs, the override (circle) is on the moved meeting.
- [ ] E3 Set efforts on a few tasks due this week → the states match your own judgement.
- [ ] E4 Ask Claude Code to create a task "Prepare offsite" due in 3 days with effort M and then read today's schedule → the answer includes free time and the task in "work on" with a state.

## Results

| Date | Checked by | Result | Notes |
|---|---|---|---|
| | | | |
