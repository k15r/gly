# Design

## Context

- `TaskPageView.fields` uses `Picker`s for priority, effort and status, a `DatePicker` for the due date plus "Add time"/"Remove time" buttons, and a separate snooze `DatePicker` when snoozed. Tags come from `TagField` (shared with pages). `TaskProgressRow` (task-progress) and the "All parts done" banner (subtasks) sit below.
- `TaskActions` (the ⋯ and context menu) already has snooze options with "won't fit anymore" warnings, Reopen, Drop and Delete.
- `CaptureParser` understands due words: weekdays, "today", "tomorrow" and "3 nov", but only privately, inside the capture parse.

## Goals / Non-Goals

**Goals:**
- A compact row that reads like the task's facts; every change one click or a few keystrokes.
- Same look for tags on tasks, pages and meeting pages.

**Non-Goals:**
- Changing what can be set (fields, status rules).
- Keyboard navigation between chips. Possible later.

## Decisions

### T1: `PropertyChip`

A reusable capsule: SF Symbol, text and optional tint, with a faded style and "+ " prefix when empty. A click opens a popover anchored to the chip. Hovering highlights it. The tooltip names the property ("Priority", "Effort", …).

### T2: Popovers

- **Priority:** five rows (Urgent … None) with their symbols; keys 0–4 pick them and close the popover.
- **Effort:** sizes XS–XL with their configured durations ("M · 4h"), "None", and "Set remaining…" when the task has an effort and no estimated parts (reusing the stepper from `TaskProgressRow`).
- **Due and snooze share one layout (`DatePopover`):** an optional caption, a row of quick-pick buttons, a graphical calendar, and a row of actions. Both use the neutral chip colors; orange only marks the "won't fit" warning.
  - **Due:** quick picks Today, Tomorrow, Mon, +1 week; the calendar; "Add time" (a time field) or "Remove time"; "Remove".
  - **Snooze:** caption "Due … stays"; quick picks Tomorrow (or +1 day), Mon, +1 week, each with the `Planning.fits` warning; the calendar from tomorrow on; "Wake now" while snoozed.
  - A typed-date field was tried first and dropped after checks: the calendar is enough.

Every choice sends one command, so it's one undo step.

### T3: `DateWords`

The day words move from `CaptureParser` into a public `DateWords.parse(_ text:, today:) -> (day: LocalDay, time: String?)?`, which also accepts a trailing `HH:mm`. `CaptureParser` calls it, so capture's behavior is unchanged (its tests keep passing). The due popover no longer uses it (see T2); it stays as capture's parser and for a future typed-date input.

### T4: Layout

- **Title row:** completion button, title, ⋯ menu.
- **Chip row:** priority, effort, due, snooze, then the tags as chips in their color with ✕ on hover (a click opens the tag page), and a faded "+ Tag" chip that opens the tag menu (existing tags as a tree, "New tag…"). All chips share one style (`ChipStyle`).
- **Below:** the Progress row and the "All parts done" banner as before, then the notes (live preview) and the backlinks.
- **No status picker:** Reopen and Drop are in the ⋯ menu.

### T5: Pages and meeting pages

Their tag rows use the same tag chips and "+" popover, through the shared tag row component.

## Risks / Trade-offs

- **[Discoverability without labels]** Chips have no "Priority:" label. → Icons, tooltips, and the faded "+ Effort" / "+ Due" invitations.
- **[Popover focus]** The due text field has focus when the popover opens, so typing works immediately; Esc closes the popover.
