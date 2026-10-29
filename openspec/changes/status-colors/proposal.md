# Proposal

## Why

The task page now has a calm, consistent look: a title row and a row of chips. Task rows elsewhere (day view, task list, tag pages, search) still mix a plain circle, priority symbols, differently styled pills and colored words. Status colors grew one at a time: blue "today ≥", orange "due today", red "overdue/can't fit", purple "back from snooze", green "done". Each makes sense alone, but nothing ties them together.

## What Changes

- **One status palette:** a fixed set of meanings and colors used everywhere: overdue/can't fit red, due today and warnings orange, needs work today blue, snoozed/back from snooze purple, done green, secondary gray. Color is never the only signal: an icon or text always accompanies it, and the details live in the tooltip.
- **Task rows in the chip language:** a thin bar on the left in the row's status color (the reason in its tooltip), the title, and compact chips for effort (with what's left), due date, parts ("2/5") and tags in the same style as the task page. Hovering shows quick actions (snooze, effort, open) instead of the separate priority menu.
- **Appointments** show their calendar color as a bar, like task rows show their status.

## Capabilities

### New Capabilities

- `appearance`: how gly looks across screens: the status palette and the task row layout.

### Modified Capabilities

None at the behavior level; the reasons rows give ("overdue", "today ≥ 2h", "back from snooze") stay as specified in `day-view` and `daily-planning`, only their presentation changes.

## Impact

- App: a shared `StatusColor` palette; `TaskRow` rebuilt with the status bar, compact chips (`ChipStyle` at a small size) and hover actions; the day view's planning notes and the appointment rows use the palette.
- No data, core or MCP changes.
