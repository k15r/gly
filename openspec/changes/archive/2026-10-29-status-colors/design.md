# Design

## Context

- `TaskRow` (`TaskViews.swift`) is used in 6 places: the day view (Today and Coming up), the past-day list, the task list, tag pages and search. It shows a completion circle, a priority symbol, the title, then a caption line with "overdue", the due date, `EffortChip`, a `PlanNote` (colored bold text), "back from snooze", "until …", the part count, "… left" and `TagChip`s, plus a priority menu at the right.
- The task page uses `PropertyChip` and `ChipStyle` (task-properties T1) and the popovers `PriorityPicker`, `DuePicker` and `SnoozePicker`.
- Status colors are set ad hoc in `DayView.todayNote`/`comingUpNote` (`PlanNote.color`), in `TaskRow` and in `CapacityIndicator`.

## Goals / Non-Goals

**Goals:**
- One source of truth for status colors.
- Rows that read like the task page, with the details in tooltips.

**Non-Goals:**
- Other screens' layouts (pages, meetings): later, with the same palette.
- User-chosen accent colors.

## Decisions

### C1: `StatusColor`

An enum with the cases `overdue`, `dueToday`, `needsWork`, `snoozed`, `done` and `secondary`, mapping to system colors (`.red`, `.orange`, `.blue`, `.purple`, `.green`, `.secondary`), each with an SF Symbol. `PlanNote` carries a `StatusColor` instead of a `Color`. The day view, the rows and the task page chips (overdue due date) use it.

### C2: Row status

A function `rowStatus(task, plan item, day)` returns the strongest applicable status:
1. can't fit or overdue (red)
2. due that day (orange)
3. needs work that day (blue)
4. back from snooze (purple)
5. none

It also returns a tooltip text (e.g. "overdue since Tue", "can't fit: needs 6h, 2h free until due", "back from snooze (was until Wed)"). The bar is 3 pt wide, full row height, with rounded ends.

### C3: Row layout

- **Main line:** the completion circle, the title, and the existing plan note as text at the end ("today ≥ 2h"), in the status color with its icon.
- **Second line:** compact chips (`ChipStyle` with a `.caption` size variant) for effort/left, due date, parts and tags.
- **Hover:** small borderless icon buttons at the right for snooze (opens `SnoozePicker` in a popover), effort (opens the effort list) and open. The priority menu goes away; priority shows as the leading symbol, as on the task page.

### C4: Appointment bars

`AppointmentRow` already draws a 4 pt bar in the calendar color. It gets rounded ends and the same width as the status bar, so both columns line up.

## Risks / Trade-offs

- **[Denser rows]** Chips take more height than plain text. → The caption-size variant and the second line only when there is something to show.
- **[Hover-only actions]** They're not discoverable on their own. → The same actions stay in the context menu.
