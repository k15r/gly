# Tasks

## 1. Project scaffolding

- [ ] 1.1 Create `Packages/WorkDashCore` (library + test target, GRDB 7.x dependency, macOS 14) with the folder layout from design L1; verify `swift build` and an empty `swift test` succeed
- [ ] 1.2 Create `project.yml` at the repo root with targets `WorkDash` (app, sandboxed, app group, calendar usage description) and `WorkDashAgent` (tool, sandboxed, app group, embedded Info.plist) linking `WorkDashCore`, plus the launch agent plist copied to `Contents/Library/LaunchAgents`; verify `xcodegen generate` succeeds and the generated project is git-ignored
- [ ] 1.3 Add `scripts/build.sh` (generate + `xcodebuild` with `-allowProvisioningUpdates`, team `DB33H6YGK7`); verify it builds a signed app whose bundle contains `Contents/MacOS/WorkDashAgent` and the launch agent plist, and that `codesign --verify --deep --strict` passes

## 2. Store foundation (WorkDashCore)

- [ ] 2.1 Implement the `v1` migration from design L3 (items, tags with `name_key` partial unique index, item_tags, change_log with `batch`/`redo_of`, `live_*` views); verify with tests that migrating an empty database creates all tables, views and constraints, and that unknown enum values are rejected
- [ ] 2.2 Implement the change-log write path (insert/update/soft delete in one batch per command, per-field old/new values, writer) and soft delete cascading to `item_tags`; verify with tests for logged fields, the writer and the tombstone cascade
- [ ] 2.3 Implement undo and redo per writer (design L6), including a new change clearing the redo chain and undo of create = tombstone; verify with tests: delete → undo restores the task with tags; edit of two fields undone as one step; redo after undo; undo never touches another writer's batch
- [ ] 2.4 Implement `ExternalChangeWatcher` and a read-only `DatabasePool` factory; verify with a test that a write from a separate process (sqlite3 CLI) triggers a `ValueObservation` update on the read-only pool

## 3. Tags (WorkDashCore)

- [ ] 3.1 Implement `TagName` normalization and validation (trim, empty-segment rejection, case-folded `name_key`, first-entered casing kept); verify with tests covering the scenarios of `specs/tags` "Tag names"
- [ ] 3.2 Implement the descendant filter as an uncorrelated `IN` subquery, plus autocomplete (prefix + next segment, ordered by usage); verify with tests: `project` matches `project/atlas` and `project/atlas/logs`, `person/al` doesn't match `person/alex`, `person/` suggests both person tags
- [ ] 3.3 Implement the tag list with roll-up open-task counts and group nodes for intermediate segments; verify with a test matching the "Tag hierarchy with counts" scenario

## 4. Tasks (WorkDashCore)

- [ ] 4.1 Implement Codable commands and results (`createTask`, `updateTask`, `setStatus`, `deleteTask`, `setTags`, `undo`, `redo`, `reconcileSnoozes`, `ping`) and the `CommandHandler` with validation (non-empty title, enums, tag rules); verify with tests for each command's effect, its change-log batch and each validation error
- [ ] 4.2 Implement the task queries: task list (open + snooze-reached, sort per design L3, done/dropped views with most recent first), tasks for a day (due that day + overdue when today, snoozed handling); verify with tests matching the "Default sorting", "Due and overdue tasks today" and "Future day" scenarios
- [ ] 4.3 Implement floating due date/time and snooze handling (`due_day`, `due_time`, `snoozed_until`, `reconcileSnoozes`); verify with tests for date-only vs timed tasks, snooze reopening on its date, and a DST-transition day

## 5. Calendar (WorkDashCore)

- [ ] 5.1 Implement the `EventSource` protocol, value types (`CalendarInfo`, `Appointment`) and a fake source for tests; verify the fake can drive the day model tests below
- [ ] 5.2 Implement `EventKitSource` (permission request/status, calendar list with account grouping and colors, day query with DST-safe bounds, cancelled rule incl. "Canceled:"/"Abgesagt:" prefix, change notifications debounced, `refreshSourcesIfNecessary` every 5 min); verify by a test that the cancellation rule and title stripping work on value inputs, and manually via 8.2
- [ ] 5.3 Implement per-source "last change seen" tracking with window fingerprints (design L7); verify with a fake-source test that only a source whose events changed gets a new timestamp
- [ ] 5.4 Implement `DayModel` (all-day vs timed split, overlap kept, midnight-spanning on both days, past/current/upcoming for a given `now`, tasks for the day); verify with tests for each `specs/day-view` scenario that doesn't need UI

## 6. Agent (WorkDashAgent)

- [ ] 6.1 Implement the XPC protocol in Core (`perform(command:writer:reply:)` with JSON `Data`) and the agent `main` (Mach listener on `DB33H6YGK7.dev.k15r.workdash.agent`, team code-signing requirement, read-write pool in the app group container, migrations on start); verify with an in-process integration test using an anonymous `NSXPCListener` endpoint that `ping`, `createTask` and `undo` round-trip
- [ ] 6.2 Verify the built agent end to end: after the app registers it, `ping` from the app succeeds, the database file exists in the app group container, and killing the agent process leads to an on-demand restart on the next command

## 7. Mac app (WorkDash.app)

- [ ] 7.1 Implement the app shell: agent registration via `SMAppService`, status banner when writing is disabled (with "Open Login Items"), read-only store connection with the watcher, writer identity `user@<host>`, Developer menu with "Unregister agent"; verify manually that a fresh launch registers the agent and the banner appears when the agent is disabled
- [ ] 7.2 Implement calendar permission UI and the calendar list (grouped by account, colors, show/hide persisted in UserDefaults, new calendars visible); verify manually that hiding "Birthdays" survives a restart and that the denied state shows the settings button
- [ ] 7.3 Implement the day view (header with date and per-source refresh indicators, all-day section, timeline with current/past styling via `TimelineView`, tasks-for-the-day section with complete/open/new, empty and no-access states, ⌘←/⌘→/⌘T/⌘N); verify manually against the `specs/day-view` scenarios with the real calendars
- [ ] 7.4 Implement the task list (sorting, Open/Done/Dropped switch, inline priority and completion, tag filter from the tag list with counts) and the task edit form (title required, notes text, priority, status/snooze, due date with optional time, tags with autocomplete, explicit confirm); verify manually against the `specs/tasks` and `specs/tags` scenarios
- [ ] 7.5 Implement Undo/Redo menu routing (store undo/redo via the agent; text undo while a text field has focus) and midnight/launch `reconcileSnoozes`; verify manually: edit → ⌘Z restores, ⌘⇧Z redoes, ⌘Z while typing undoes text only

## 8. Integration checks

- [ ] 8.1 Run the full Core test suite and the build script from a clean checkout; verify both succeed with no warnings about signing or entitlements
- [ ] 8.2 Manual end-to-end check on the SAP Mac, documented in `docs/manual-checks.md`: SAP + iCloud appointments on one day, a meeting moved in Outlook appears at the new time without refresh, an organizer-cancelled meeting shows struck through, the refresh indicator updates, a task completed in the task list disappears from the day view at once, and all data survives quitting and a reboot
- [ ] 8.3 Verify no real names of people or projects appear in code, tests, fixtures or docs (grep for the known names returns nothing); verify `openspec validate mac-day-view-and-tasks --strict` passes

## Workflow follow-up

- Archive `foundation-spikes` once this change is underway (its decisions are referenced here).
- Archive `mac-day-view-and-tasks` after review; then propose the MCP change (`get_schedule`, task tools) on top of the agent.
