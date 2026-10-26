# Proposal

## Why

The day view shows only what's due today. That's too late for planning: a task due on Thursday that needs a day of work has to be started on Wednesday at the latest, and how much time is left depends on how many meetings stand in the way. The day view should tell me what to work on today so everything is done on time, based on how much work each task is and how much free time my calendar really leaves. Accepted meetings aren't always unskippable, so I must be able to say which ones count.

## What Changes

- **Effort on tasks:** a new built-in field with T-shirt sizes `XS`, `S`, `M`, `L` and `XL`.
  - How much time each size roughly means is configurable in Settings. Defaults: 30 min, 2 h, 4 h, 1 day, 3 days.
  - It's shown as a chip on task rows and set in the task page's field row.
  - Agents can set it via MCP.
- **Working hours:** one configurable daily window, 09:00–17:00 by default, the same every day.
- **Free time:** working hours minus the appointments that block time.
  - **Defaults from the calendar:**
    - declined, cancelled and "free" appointments don't block
    - all-day appointments don't block, unless they're out-of-office or busy
    - tentative and unanswered appointments count half ("maybe")
    - accepted appointments block
  - **Override:** a small menu on each appointment in the day view: *blocks*, *optional* (counts half) or *ignore*, for this occurrence or for the whole series.
- **"Work on" in the day view:**
  - Besides the tasks due today, the day view lists the open tasks due within the next *N* days. *N* defaults to 5, is configurable, and can be switched in the header.
  - Each task's effort is compared on its own with the free time left until its due date. The result is a state: *ok*, *start today*, *tight* or *late*. The list is sorted by urgency.
  - Tasks without an effort appear without a state, marked "no estimate".
- **Capacity in the header:** today's free time, as a number and a small bar.
- **Appointment identity (foundation for annotations):** an override is stored as a minimal annotation, with the appointment key and a snapshot (title, start, end, calendar).
  - The key and the two-stage matching follow foundation spike D4: exact key, then fuzzy matching on the snapshot, key migration on every calendar change, and the states `active`, `cancelled` and `gone`.
  - Series overrides follow series splits.
- **MCP:**
  - `get_schedule` also returns the free time and the "Work on" list with states.
  - The task tools read and write `effort`.

Not in this change: appointment notes, prep view, series tag rules and appointment leaves in the tag tree (next change: annotations proper); a time-grid layout of the day; allocating free time across tasks; per-weekday working hours; local appointments.

## Capabilities

### New Capabilities

- `daily-planning`: effort sizes, working hours, how appointments block time, free time per day, the horizon and the "Work on" list with its states, and the capacity indicator.
- `appointment-annotations`: stable identity of calendar appointments (key, snapshot, matching, life-cycle states) and blocking overrides per occurrence and per series. Notes, prep view and series tags will extend it later.

### Modified Capabilities

- `tasks`: tasks get an effort field, shown on rows and editable on the task page.
- `agent-access`: `get_schedule` includes free time and the "Work on" list, and the task tools carry `effort`.

## Impact

- **Store:** an additive `v4` migration.
  - `items` gets `effort`, and columns for annotations (`kind = 'event_note'`, already allowed): the appointment key, snapshot fields, state and blocking override.
  - A new synced table `series_rules` holds the blocking override per series.
- **Core:**
  - effort and planning settings in `SharedSettings`
  - the blocking classification and free-time calculation (pure, testable with fake calendars)
  - the appointment key and matching, with key migration on calendar changes
  - "Work on" queries
  - new commands `setBlocking` (occurrence or series) and effort in `TaskDraft`/`TaskPatch`
- **Calendar adapter:** `EventKitSource` exposes per occurrence the external id, original start, availability, my participation status and the organizer flag. Exchange's support for availability and participation is checked first.
- **App:**
  - the day view gets a "Work on" section, a horizon switch, a capacity header and the appointment menu
  - Settings gets a Planning pane (working hours, sizes, horizon)
  - task rows and the task page show effort
- **MCP:** `get_schedule` gains fields; task tools gain `effort`. Existing fields stay compatible.
