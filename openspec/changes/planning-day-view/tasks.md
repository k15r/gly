# Tasks

## 1. Unknowns first

- [x] 1.1 Probe on the SAP Mac which attendance data EventKit delivers for Exchange and iCloud (availability, current-user participant status, organizer flag, external id with RID) for accepted, tentative, declined, unanswered, out-of-office and "free" appointments; record the findings and the fallbacks used in `design.md` Q1

## 2. Core: calendar data and planning logic

- [x] 2.1 Extend `Appointment` with `identity` (calendar, baseID, originalStart), `availability`, `myStatus`, `isOrganizer`, fill them in `EventKitSource` and `FakeEventSource`, and add `AppointmentKey` (occurrence and series keys); verify with tests that RID suffixes are stripped, the original start comes from the RID when present, and keys are equal before and after a simulated move
- [x] 2.2 Implement `Blocking.classify` (overrides first, then the automatic rules of design Q5) as a pure function; verify with table-driven tests covering "Declined meeting", "Tentative meeting", "Out of office", cancelled, availability free, all-day busy/free, and override precedence ("Exception in an optional series")
- [x] 2.3 Implement `FreeTime.minutes(from:to:...)` (working window per local day, union of blocking intervals, half of maybe-only intervals); verify with tests for "Overlapping meetings", "Later today", "Change working hours", a DST day, an all-day block, and now inside a meeting
- [x] 2.4 Implement `TaskQueries.upcoming` (open tasks due tomorrow…today+N, snoozed only from their snooze date) and `Planning.plan` (needed today, can't fit, Today list, load, Coming up with start by); verify with tests for "Task needing work today", "Due today without estimate", "Can't fit", "Enough time later", "Overbooked day", "Start by", "Horizon", and a timing test for a 14-day horizon with 200 appointments

## 3. Core: store and commands

- [x] 3.1 Add the `v4` migration (items: effort, event_* columns, blocking; `series_rules` synced table + live view) and effort in `TaskDraft`/`TaskPatch`/`TaskItem`; verify with schema tests (migration from v3, CHECK constraints, `series_rules` in `syncedTables`) and command tests for "Effort" and invalid sizes
- [x] 3.2 Add `setBlocking` (occurrence → create/update event_note annotation with snapshot; series → create/update rule; nil → automatic) with undo labels, and queries for annotations and rules by key/series; verify with tests for "Skip one meeting", "Optional series", "Back to automatic", one undo step each
- [x] 3.3 Implement `AnnotationMatcher.reconcile` (exact key, fuzzy candidates, migrate/ambiguous/gone, snapshot update, series-rule base-id adoption) and the `reconcileAnnotations` / `resolveAnnotation` commands; verify with tests for "Meeting moved", "Ambiguous match", "Series split", "Annotated meeting deleted", and that annotations outside the window are untouched
- [x] 3.4 Add the planning settings to `SharedSettings` (working hours, effort minutes with defaults derived from the working day, horizon); verify with tests for defaults, "Default sizes" and "Configured size"

## 4. Agent and MCP

- [x] 4.1 Run `AnnotationMatcher` in the agent after calendar changes (debounced), at launch and at midnight, written as `system@<device>`; verify with an integration test using `FakeEventSource.change` that a moved occurrence keeps its override
- [x] 4.2 Extend `get_schedule` (per appointment `counts_as`/`reason`, `free_minutes`, today's `today` / `coming_up` lists with reasons, needed today, can't fit and start by) and the task tools with `effort`; verify with MCP tests for "Planning data", "Agent estimates a task", and that existing fields are unchanged

## 5. App

- [ ] 5.1 Add the Settings "Planning" tab (working hours, sizes with derived defaults, horizon); verify manually that changes update the day view at once
- [ ] 5.2 Add effort to task rows (chip), the task page field row (control) and the task context menu; verify manually "Effort" and "Set effort on the task page" including one ⌘Z
- [ ] 5.3 Add the planning model to the day view: capacity header with bar, the Today list with load header, Coming up with horizon picker; verify manually "Busy day", "Overbooked day", "Switch the horizon", and that the lists update when a meeting is declined ("Meeting declined in Outlook")
- [ ] 5.4 Add the appointment menu (Automatic/Blocks/Optional/Ignore × occurrence/series), the weight icon on rows, and the ambiguity banner; verify manually "Skip one meeting", "Optional series", "Back to automatic", and that free time updates immediately

## 6. End to end

- [ ] 6.1 Manual checks in `docs/manual-checks-planning.md` on the SAP Mac: real week with Exchange meetings; ignore one occurrence and make a series optional; move an overridden meeting in Outlook and see the override follow; set efforts on a few tasks due this week and compare states with your own judgement; an agent creates an estimated task and reads `get_schedule`; neutral test data only

## Workflow follow-up

- Run `/opsx:verify planning-day-view`, then archive after the manual checks pass.
- Next change: annotations proper (appointment notes as pages, prep view, series tag rules, appointment leaves in the tag tree).
