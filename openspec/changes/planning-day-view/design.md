# Design

## Context

- **Calendar access:** `EventKitSource` in Core reads appointments in the app and in the agent. Its `Appointment` carries title, times, all-day flag, cancelled flag, location, organizer and attendees, but no identity beyond a process-local id.
- **Appointment identity:** foundation spike D4 defined and verified the key on iCloud and SAP Exchange, `calendar/baseId@originalStart`, and two-stage matching. Neither is implemented yet.
- **Store:** the `items` table already allows `kind = 'event_note'`. All writes go through `CommandHandler` in the agent. `SharedSettings` (app-group defaults) is read by both processes.
- **Day view:** built from `DayModel` (appointments plus `tasksForDay`). The agent's `get_schedule` reuses it.

Motivation and scope are in `proposal.md`, behavior in the specs of this change.

## Goals / Non-Goals

**Goals:**
- **Planning logic is pure and testable:** classification, free time, states. It's computed the same way in the app and the agent.
- **Appointment identity and matching are built once,** so the annotations change only adds content (notes, prep, series tags).
- **No change to how appointments are read** for views that don't need planning.

**Non-Goals:**
- Allocating free time across tasks.
- A time grid.
- Per-weekday working hours.
- Local appointments.
- Writing anything back to calendars.

## Decisions

### Q1: The calendar adapter exposes identity and attendance

`Appointment` gains:
- **`identity`** with `calendarID`, `baseID` and `originalStart`:
  - `baseID` is `calendarItemExternalIdentifier` without its `/RID=…` suffix
  - `originalStart` is the RID value if present, otherwise `occurrenceDate`
- **`availability`:** `busy`, `free`, `tentative`, `unavailable` (out of office) or `unknown`.
- **`myStatus`:** `accepted`, `declined`, `tentative`, `pending` or `none`, from the attendee with `isCurrentUser`. It's `none` when there are no attendees.
- **`isOrganizer`:** whether the organizer is the current user.

Everything stays inside `EventKitSource`. `FakeEventSource` gets the same fields for tests.

**Risk:** Exchange accounts may report availability as not supported, or leave the current user out of the attendees. Task 1.1 probes this on the SAP Mac. Fallbacks: treat unknown availability as busy, and no status as accepted, so the appointment blocks. That's the safe side: free time is underestimated, never overestimated.

### Q2: Keys

- **Occurrence key:** `"\(calendarID)/\(baseID)@\(Int(originalStart.timeIntervalSinceReferenceDate))"`.
- **Series key:** `"\(calendarID)/\(baseID)"`.

Both are computed in Core (`AppointmentKey`), not in the adapter, so tests can build them from fake data. The calendar part uses `calendarIdentifier`. Cross-device calendar identity stays an open point from D4, to be settled with the iOS target.

### Q3: Storage (`v4` migration, additive)

- **`items.effort`** (`XS` … `XL`, nullable, CHECK).
- **Annotations are `items` with `kind = 'event_note'`.** `title` holds the snapshot title, `body` stays empty until notes exist. New nullable columns:
  - `event_key` (indexed), `event_series`
  - `event_calendar`, `event_start`, `event_end`, `event_organizer` (the snapshot)
  - `event_state`: `active`, `cancelled`, `gone` or `ambiguous`
  - `blocking`: `blocks`, `optional`, `ignore`, or NULL for automatic
- **`series_rules`**, a new synced table with the sync columns:
  - `calendar_id`, `title`, `organizer`
  - `base_ids` (JSON array, so a rule can follow series splits)
  - `blocking`

  It's added to `Schema.syncedTables` and gets a `live_series_rules` view.
- **Commands:**
  - `setBlocking(appointment: AppointmentSnapshot, scope: .occurrence | .series, value: Blocking?)`. `nil` means automatic. It creates or updates the annotation or rule as one batch, so ⌘Z undoes it.
  - Effort goes into `TaskDraft` and `TaskPatch`.
- **Undo labels:** "Ignore "Weekly sync" (this occurrence)", "Optional "Info session" (series)", "Effort of "…"".

### Q4: Matching and key migration run in the agent

The agent already reads EventKit (`EventKitSource.onChange`, debounced). After each change, at launch and at midnight, it runs `AnnotationMatcher.reconcile`. That's a pure function over:
- the live annotations whose snapshot start falls within a window (today − 7 to today + 60 days)
- the appointments EventKit returns for that window

For each annotation, the function returns one of:
1. **exact key match:** update the snapshot (moves and renames) and set the state from the cancelled flag (`active` or `cancelled`)
2. **no exact match:** look for candidates with the same calendar, the same day of the original start, an equal title (case-folded) and the same organizer
   - exactly one candidate → migrate the key
   - several candidates → `ambiguous`
3. **no candidate:** `gone`

The agent applies the result with a `reconcileAnnotations` command, written as `system@<device>`. Annotations outside the window are left alone.

**Series rules** match an appointment when its `baseID` is in the rule's `base_ids`. Otherwise they match on the same calendar, the same title (case-folded) and the same organizer, and in that case the new `baseID` is added to the rule. That's how a rule follows series splits.

**Ambiguous annotations:** the day view shows a banner, "Which appointment does "…" belong to?", listing the candidates. Choosing one sends `resolveAnnotation(id, key)`. Until then the override is not applied.

### Q5: Classification

`Blocking.classify(appointment, override) -> (Weight, Reason)`:
- **Weight:** `blocks` (1.0), `maybe` (0.5) or `free` (0).
- **Reason:** `automatic` or `override(occurrence | series)`.

The order:
1. occurrence override
2. series override
3. automatic:
   - cancelled or declined → free
   - availability free → free
   - all-day: unavailable (out of office) or busy → blocks the whole day, otherwise free
   - tentative or pending → maybe
   - otherwise → blocks

Override mapping: *blocks* → blocks, *optional* → maybe, *ignore* → free. All of this is a pure function, with table-driven tests.

### Q6: Free time

`FreeTime.minutes(from: Date, to: Date, appointments: [(DateInterval, Weight)], workingHours: (start, end))`:
- For each local day in the range (DST-safe via `LocalDay`), intersect the working window with `[from, to]`.
- Subtract the union of blocking intervals, then half of the union of maybe-only intervals (maybe time not already covered by blocking time).
- Sum the results.

This covers "today from now on" (from = now) and "until due" (to = end of the due day, or the due time). It's a pure function, with tests for overlaps, DST days, all-day blocks and "now" in the middle of a meeting.

### Q7: Planning model

`Planning.workOn(tasks, today, now, horizon, sizes, workingHours, freeTime: (Date, Date) -> Minutes) -> [WorkOnItem]`:
- `WorkOnItem` has the task, the effort in minutes, the free minutes until due, and the state.
- **Thresholds:**
  - late: free < effort
  - tight: free < 1.5 × effort
  - start today: free < 2 × effort, or due tomorrow
  - ok: otherwise
- **Sorting:** state, then due date, then priority.

Tasks come from a new query `TaskQueries.upcoming(day: today, horizon: N)`: open tasks with due date from tomorrow to today + N, and snoozed tasks only from their snooze date. Due-today and overdue tasks keep their existing section, but get states too, so the most urgent ones are visible there.

The appointments for the horizon come from one `EventSource.appointments(overlapping: today…today+N)` call, together with the annotations and series rules from the store.

### Q8: Settings

`SharedSettings` gains `workingStart` and `workingEnd` (minutes after midnight, default 540–1020), `effortMinutes` (a map from size to minutes; defaults 30/120/240, with `L` and `XL` derived from the working-day length unless set) and `horizonDays` (default 5). The agent reads them on demand.

The app's Settings gets a "Planning" tab next to "Agents".

### Q9: UI

- **Day view header:** "free 3h 30m" plus a capacity bar (free over working length), and a horizon menu (3, 5, 7, 14 days).
- **Sections:** "Due today" (with states), then "Work on", each row showing the effort chip, due date and a state badge.
- **Appointment rows:**
  - a small menu button and a context menu: Automatic / Blocks / Optional / Ignore, × This occurrence / Whole series
  - an icon showing a non-automatic weight (dimmed for ignore, half-filled for optional)
  - the ambiguity banner (Q4)
- **Effort:** a chip on `TaskRow`, a segmented control or menu on the task page, and S/M/L in the task context menu.
- **Recomputation:** planning updates from the existing observations (tasks, calendar changes, the annotation and rule query) and the `Clock` tick.

### Q10: MCP

- **`get_schedule`** adds per appointment `counts_as` (`blocks`, `maybe`, `free`) and `reason`, plus `free_minutes`. For today it adds `work_on: [{task…, effort, free_until_due_minutes, state}]`.
- **Task encoding** adds `effort`; `create_task` and `update_task` accept it.
- Tool descriptions explain the sizes and states.

## Risks / Trade-offs

- **[Exchange doesn't expose availability or my participation status]** → Probed first (task 1.1). The fallback assumes busy and accepted, so the appointment blocks: planning stays safe and less precise. The user can override anything.
- **[Fuzzy matching attaches an annotation to the wrong appointment]** → Exact title, organizer, calendar and day are all required. Several candidates are never guessed; they're asked about. Everything is logged and undoable.
- **[Series rules matching unrelated series with the same title]** → Calendar and organizer must match too. Rare in practice; the user can set an occurrence override against it.
- **[States per task overstate free time when several tasks compete]** → An accepted simplification (user choice). The header's capacity bar keeps the total in view.
- **[EventKit range query cost for 14 days]** → One query per recompute, already debounced. Measured in task 2.4.

## Migration Plan

- **`v4` is additive:** new columns and a new table. Older builds ignore them (verified behavior from `v2`).
- **Defaults** apply until the user changes settings. Existing tasks have no effort and show "no estimate".
