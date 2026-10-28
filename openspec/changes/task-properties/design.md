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
- **Due:**
  - quick picks: Today, Tomorrow, Next Monday, In a week
  - a text field parsed live with `DateWords` (preview below it, Return applies)
  - a graphical `DatePicker`
  - "Add time" (a time field) or "Remove time"
  - "Remove due date"
- **Snooze:**
  - not snoozed: "Tomorrow", "Next Monday" and a date, each with the `Planning.fits` warning as in `TaskActions`, under a "Due … stays" heading
  - snoozed: the date, "Snooze 1 more day" and "Wake now" (status open)

Every choice sends one command, so it's one undo step.

### T3: `DateWords`

The day words move from `CaptureParser` into a public `DateWords.parse(_ text:, today:) -> (day: LocalDay, time: String?)?`, which also accepts a trailing `HH:mm`. `CaptureParser` calls it, so capture's behavior is unchanged (its tests keep passing).

### T4: Layout

- **Title row:** completion button, title, ⋯ menu.
- **Chip row:** priority, effort, due, snooze, then the tags as chips with ✕ on hover and a "+" chip that opens `TagField`'s suggestions in a popover.
- **Below:** the Progress row and the "All parts done" banner as before, then the notes (live preview) and the backlinks.
- **No status picker:** Reopen and Drop are in the ⋯ menu.

### T5: Pages and meeting pages

Their tag rows use the same tag chips and "+" popover, through the shared tag row component.

## Risks / Trade-offs

- **[Discoverability without labels]** Chips have no "Priority:" label. → Icons, tooltips, and the faded "+ Effort" / "+ Due" invitations.
- **[Popover focus]** The due text field has focus when the popover opens, so typing works immediately; Esc closes the popover.
