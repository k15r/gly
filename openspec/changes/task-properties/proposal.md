# Proposal

## Why

The task page's field row is a line of standard macOS pickers ("Priority [None ⌃]", "Effort [– ⌃]", "Status [Done ⌃]"). It's wide, looks like a settings form, and a few things are clumsy: setting a date means a date picker, snoozing hides in a status picker plus a date, and the status picker duplicates the completion button. A compact row of chips that show their value and open small popovers reads better and is faster.

## What Changes

- **Property chips** under the title: priority, effort (with what's left), due date, snooze and tags. Each shows its value, or a faded "+ Due" / "+ Effort" when empty, and opens a small popover.
- **Due date popover:** quick picks (Today, Tomorrow, Next Monday, In a week), a text field that understands quick capture's date words ("fri", "tomorrow", "3 nov", optionally a time "14:00"), a calendar, add/remove time, and remove.
- **Snooze chip:** "Snoozed until Mon" while snoozed (with "Wake now"), otherwise faded "+ Snooze". The popover has Tomorrow, Next Monday and a date, with the existing "won't fit anymore" warnings.
- **Priority and effort popovers** list the values; number keys pick them. The effort popover also offers "Set remaining…" when that applies.
- **The status picker is removed:** done is the completion button, snooze has its chip, and drop/reopen live in the ⋯ menu.
- **Same chip style** for the tag rows of pages and meeting pages.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `tasks`: the task page's layout: property chips with popovers, no status picker, notes in the live-preview editor.

## Impact

- App: a `PropertyChip` component and popovers in `TaskPageView`; the shared tag row in `TaskViews` (used by pages and meeting pages); the status picker removed.
- `GlyCore`: quick capture's date words exposed as a reusable parser (`DateWords`), plus an optional time.
- No data or MCP changes. Follows `live-preview` (the notes part of the requirement).
