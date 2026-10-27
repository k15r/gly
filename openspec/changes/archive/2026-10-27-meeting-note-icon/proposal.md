# Proposal

## Why

In the day view, an appointment with notes shows a small notes icon, but clicking it does nothing of its own: the click opens the appointment's popover, and only its "Notes" button leads to the meeting page. The icon looks like a shortcut to the notes, so it should be one.

## What Changes

- Clicking the notes icon on an appointment in the day view opens that meeting's page with its notes directly, without the popover.
- The icon's tooltip says what the click does ("Open notes").
- Clicking anywhere else on the appointment row still opens the popover, as before.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `meeting-pages`: adds how the notes mark on an appointment in the day view leads to the meeting page.

## Impact

- `Apps/Mac/App/DayView.swift` (`AppointmentRow`): the notes icon becomes a button that navigates to the meeting page.
- No change to stored data, the agent or the MCP tools.
