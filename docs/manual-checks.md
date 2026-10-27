# Manual checks: mac-day-view-and-tasks

Build and run: `scripts/build.sh && open build/Build/Products/Debug/gly.app`.
Mark each item with ✅ / ❌ and a note. Use neutral test data only (no real names).

## A. App shell and agent (task 7.1)

- [x] A1 First launch: no "Writing disabled" banner (or, if macOS asks, approve the gly login item and press **Retry** in the banner).
- [x] A2 System Settings → General → Login Items & Extensions: "gly" is listed and allowed.
- [x] A3 Developer → Unregister Agent → the yellow banner "Writing disabled …" appears and New Task is disabled. Quit and reopen gly → banner gone again.

## B. Calendars (task 7.2)

- [x] B1 First launch asks for calendar access → allow.
- [x] B2 Sidebar → Calendars: calendars grouped by account (Exchange, iCloud, Subscribed, Other) with their colors.
- [x] B3 Hide "Birthdays" → its entries vanish from the day view. Quit + reopen → still hidden.
- [ ] B4 (optional) Revoke calendar access in System Settings → day view shows "No calendar access" with a settings button, tasks still work. Re-allow afterwards.

## C. Day view (task 7.3)

- [x] C1 Opens on today with weekday + date. SAP and iCloud appointments in one list, ordered by start time, each with color bar and calendar name.
- [x] C2 All-day entries (e.g. a holiday) are listed above the timed ones.
- [x] C3 During a meeting: it's highlighted with "Now"; earlier ones are dimmed.
- [x] C4 ⌘→ / ⌘← / ⌘T switch to next / previous day / today. The Today button is disabled on today.
- [x] C5 A cancelled meeting (organizer cancelled, or "Canceled:" in the title) appears struck through with a "Cancelled" badge.
- [x] C6 Header shows per-account indicators ("Exchange: no changes since launch" → after a change: "… min ago").
- [x] C7 A free day says "No appointments"; a day without tasks says "No tasks".
- [x] C8 "New Task" in the day view (or ⌘N) while viewing tomorrow → the editor's due date is tomorrow.
- [x] C9 Click an appointment → a popover at the cursor shows title, time, calendar, location, organizer and attendees (selectable, not editable). Esc or a click outside closes it; that click doesn't reopen another popover.

## D. Tasks and tags (task 7.4)

- [x] D1 Create "Test task A" (no due) and "Test task B" due today, priority Urgent, tags `person/alex`, `project/atlas`. Both appear in Tasks; B also in today's day view.
- [x] D2 Saving without title shows "Title is required" and doesn't save.
- [x] D3 Tasks list order: urgent first, then by due date (no due date last).
- [x] D4 Change priority inline (the priority menu on the row) → list re-sorts immediately.
- [x] D5 Tick a task in the day view → it disappears there and from the Open list at once.
- [x] D6 Done / Dropped segments show completed / dropped tasks (most recently completed first).
- [x] D7 Right-click → Snooze until Tomorrow → task stays in the Open list at its position, marked "until …", and leaves today's day view (it's not shown on tomorrow's view either; tomorrow it's back as a normal/overdue task).
- [x] D8 Typing `person/` in the tag field suggests `person/alex`. Entering `project//x` shows the empty-segment error. Entering `Person/Alex` reuses the existing tag (no duplicate in the sidebar).
- [x] D9 Sidebar → Tags shows `person (n)` with `alex`, `project` with `atlas`, with open-task counts. Clicking `project` filters the task list to everything under it; the ✕ clears the filter.

## E. Undo / redo (task 7.5)

- [x] E1 Edit a task (change title + due date + a tag) → Save → the Edit menu reads "Undo Edit “…” (title, due date, tags)"; ⌘Z restores all in one step and shows the overlay (rewind arrow + task name); ⌘⇧Z redoes with a forward arrow.
- [x] E2 Delete a task (right-click → Delete) → ⌘Z brings it back with its tags.
- [x] E3 While typing in a text field, ⌘Z undoes only the typing, not a store change.

## F. End to end on the SAP Mac (task 8.2)

- [x] F1 In Outlook, move a meeting you organize (e.g. a test series) → once Apple Calendar has it, gly shows the new time without any refresh.
- [x] F2 The account indicator for Exchange updates after F1.
- [x] F3 Quit gly → reopen: all tasks unchanged. Reboot → still unchanged.

## Results

| Date | Checked by | Result | Notes |
|---|---|---|---|
| 2026-10-25 | owner | A ✅ | App shell and agent: all good |
| 2026-10-25 | owner | B ✅ | Calendars; fixed: visibility toggles didn't update (state read from UserDefaults wasn't observed) |
| 2026-10-25 | owner | C ✅ | Day view; fixed: ⌘N opened a new window instead of the task editor. Note: a private multi-day Exchange item isn't delivered by Apple Calendar (outside gly, cause under investigation) |
| 2026-10-26 | owner | D ✅ | Tasks and tags; fixed: ⌘N new window, unconfirmed tag lost on Save, tag field squeezed the editor, ticking now shows the check for 1.5 s before the task leaves, snooze reworked: snoozed tasks stay in the task list with an "until …" marker, are hidden from the day view until their date, and can be snoozed further |
| 2026-10-26 | owner | E ✅ | Undo/redo; added: overlay (rewind/forward arrow + step with task name) and named Edit menu items; fixed: one editor save was up to three undo steps |
| 2026-10-26 | owner | F ✅ | End to end: a meeting moved in Outlook showed at the new time without refresh, Exchange indicator updated, tasks survived quit and reboot. EventKit doesn't need Calendar.app running |
| 2026-10-26 | owner | C9 ✅ | Added after verify: read-only appointment popover, anchored at the cursor; a dismissing click doesn't reopen |
| | | | |
