# Design

## Context

See `proposal.md` for the motivation and `specs/` for the required behavior. This is the first production code in the repository. Constraints come from `openspec/changes/foundation-spikes/design.md` (D1–D6), whose decisions are taken as given:

- GRDB/SQLite with sync-ready conventions (UUIDs, `modified_at`/`modified_by`, tombstones, change log with batches) and `live_*` views (D1–D3).
- A launch agent inside the app bundle is the only writer of the store, registered via `SMAppService` and reached over XPC with a Mach name prefixed by the app group (D5).
- `WorkDashCore` has no AppKit/UIKit (D6).
- Uncorrelated `IN (SELECT …)` subqueries for tag filters (D3). An `ExternalChangeWatcher` is needed for cross-process observation (D3).
- Signing: free development team `DB33H6YGK7`, app group `DB33H6YGK7.dev.k15r.workdash`. XcodeGen + `xcodebuild` work on the managed Mac.

Spike code in `spikes/` is not reused. Only the techniques are.

## Goals / Non-Goals

**Goals:**
- The repository layout and build that later changes (MCP, notes, sync, iOS) extend without restructuring.
- A store schema that later additions (properties, links, recurrences, FTS) extend through additive migrations only.
- The day view and task flows from the specs, with the logic unit-tested in `WorkDashCore`.

**Non-Goals:**
- Visual polish beyond a clean, native SwiftUI layout.
- Markdown rendering (notes are plain text in a `TextEditor`).
- Persisting anything about appointments (no annotations yet, so EventKit data stays live-only).
- Login item management UI beyond status + "open Login Items".

## Decisions

### L1: Repository layout and build

```
project.yml                     XcodeGen spec (generated WorkDash.xcodeproj is git-ignored)
Packages/WorkDashCore/          Swift package, library + tests (swift test)
  Sources/WorkDashCore/
    Store/       schema, migrations, change log, undo/redo, ExternalChangeWatcher
    Tasks/       task model, commands, queries (day tasks, task list)
    Tags/        name normalization, filter, autocomplete, counts
    Calendar/    EventSource protocol, EventKit adapter, day merge, cancellation rule
    XPC/         @objc protocol + Codable command/result types
  Tests/WorkDashCoreTests/
Apps/Mac/
  App/           WorkDash.app (SwiftUI)
  Agent/         WorkDashAgent (launch agent target, XPC listener)
  LaunchAgents/  dev.k15r.workdash.agent.plist
scripts/build.sh               xcodegen generate && xcodebuild ... (one entry point)
```

- `WorkDashCore` is a local Swift package so its tests run with plain `swift test`, fast and without signing. App and agent link it.
- Bundle IDs: `dev.k15r.workdash` (app) and `dev.k15r.workdash.agent` (agent). Launch agent label `dev.k15r.workdash.store-agent`, Mach name `DB33H6YGK7.dev.k15r.workdash.store-agent`. *(Changed during implementation: the MCP spike had registered the label `dev.k15r.workdash.agent`, and its stale login-item entry blocked reuse.)*
- macOS 14+ deployment target (EventKit full-access API, `SMAppService`).
- *Alternative:* everything in the Xcode project without a package. Rejected because Core tests would need the full signed build.

### L2: Process roles: the agent writes, the app reads directly

```
 WorkDash.app                                   WorkDashAgent (login item)
 +--------------------------------+   XPC       +-----------------------------+
 | SwiftUI views                  |  commands   | CommandHandler              |
 |  ValueObservation (read-only)  |-----------> |  validate -> write + log    |
 |  EventKit (live, read-only)    |  <--------  |  undo/redo per writer       |
 +---------------+----------------+   results   +--------------+--------------+
                 | read-only pool + watcher                    | read-write pool
                 +-------------------> workdash.sqlite <-------+
                                  (app group container)
```

- **Decides D5's open point:** the app reads the database with a **query-only `DatabasePool`** and `ValueObservation`, made cross-process aware by an `ExternalChangeWatcher` on the `-wal` file (spike: ~70–115 ms latency). This keeps reactive lists simple and avoids an XPC read API now.
  - *Found during implementation (task 2.4):* GRDB ignores `notifyChanges` on `Configuration.readonly` pools, and it resets `PRAGMA query_only` on the writer connection. So the app opens a normal pool that is wrapped in **`ReadOnlyStore`**, which exposes only `read` and `observe`. "The app never writes" is enforced by having no write API (compile time), not by SQLite. Observation of external writes is tested.
- **All writes go through XPC to the agent**, which is the only process opening the database read-write. Later MCP writes reuse the same command handler.
- **EventKit is read in the app process** in this change. Nothing about appointments is persisted yet, so the agent doesn't need calendar access. The agent gets EventKit with the MCP change (`get_schedule`) and annotations. *Trade-off:* calendar permission is then requested twice, once per process. Acceptable, and decided again in the MCP change.
- On launch, the app registers the agent (`SMAppService.agent`). If the agent isn't enabled or can't be reached, the app shows a banner ("Writing disabled: WorkDash agent not enabled → Open Login Items") and stays readable. The store is created by the agent: if the database doesn't exist yet when the app starts, the app sends a `ping`, which makes the agent create and migrate it, then opens it read-only.

### L3: Store schema (v1) and conventions

Initial migration `v1` creates only what this change needs. Later changes add tables and columns through additive migrations (D3 shape preserved):

- `items`: all D2 columns plus `kind` (CHECK, only `task` used now, the full enum declared), `title`, `body`, `status`, `priority`, `due_day` (TEXT `YYYY-MM-DD`, floating local date), `due_time` (TEXT `HH:mm`, optional, floating), `snoozed_until` (TEXT `YYYY-MM-DD`), `completed_at`.
- `tags`: D2 columns plus `name` (display casing), `name_key` (normalized, see L5), `color`, `page_body`, `archived`. Partial unique index on `name_key WHERE deleted_at IS NULL`.
- `item_tags`: D2 columns plus `item_id`, `tag_id`.
- `change_log`: as in the spike (`seq`, `at`, `writer`, `batch`, `op`, `table_name`, `row_id`, `field`, `old_value`, `new_value`, `synced`, `undone`) plus `redo_of` for redo bookkeeping.
- `live_items`, `live_tags`, `live_item_tags` views.

**Floating dates for due/snooze:** personal due dates mean "this calendar day, wherever I am". Storing local day + optional wall-clock time avoids time zone shifts and makes day queries simple string comparisons (`due_day = '2026-10-27'`, overdue = `due_day < today`). *Alternative:* UTC instant. Rejected because date-only tasks would shift across time zones and DST.

**Sorting keys** (task list and day view): priority rank (`urgent`=4 … `none`=0, descending), then `due_day` (nulls last), then `due_time` (date-only before timed, treated as start of day), then `created_at`.

### L4: Commands, validation and the change log (agent)

Writes are **Codable commands** sent as JSON `Data` over one XPC method (`perform(_ command: Data, writer: String, reply: (Data) -> Void)`), so the XPC surface stays stable as commands grow:

`createTask`, `updateTask(id, fields)`, `setStatus(id, status, snoozedUntil?)`, `deleteTask(id)`, `setTags(id, [names])`, `undo`, `redo`, `reconcileSnoozes(today)`, `ping`.

- The agent validates (non-empty title, enum values, tag name rules) and returns `Result { ok(ids/changes) | error(code, message) }`. The app shows errors inline.
- Each command runs in **one transaction and one change-log batch**. Every changed field is logged with old and new value. `modified_by` and `change_log.writer` come from the `writer` argument, which the app sets to `user@<device id>`. *(Changed during implementation: a random device ID such as `mac-3f2a9c`, created once, instead of the host name, which can contain personal data.)* The agent only accepts peers signed by our team (`setCodeSigningRequirement`), so the writer string is trusted for now.
- **Soft delete** tombstones the item and its `item_tags` in the same batch.
- `setTags` diffs the current assignments: it tombstones removed `item_tags` rows, inserts new ones, and creates missing tags. Re-adding a previously removed tag inserts a new assignment row (the history stays intact).

### L5: Tags

- **Normalization** (`TagName`): trim whitespace and leading/trailing `/`; reject empty segments; `name_key` = Unicode case fold, locale-independent (`folding(options: [.caseInsensitive], locale: nil)`), so `Person/Alex` and `person/alex` collide. The display `name` keeps the first-entered casing.
- **Descendant filter:** `name_key = :k OR name_key LIKE :k || '/%' ESCAPE '\'` with `%`/`_` escaped, compiled as `items.id IN (SELECT item_id FROM live_item_tags JOIN live_tags … )` (D3 rule). The full-segment rule follows from the `'/'` in the pattern.
- **Autocomplete:** prefix match on `name_key` over live tags, ordered by usage count. After a `/`, suggest next-segment completions.
- **Tag list with counts:** fetch (tag, open task count) pairs and build the hierarchy and roll-up counts in Swift (small data). Intermediate segments without a tag row of their own (`person`) are shown as group nodes.

### L6: Undo and redo

- **The undo stack is per writer:** `undo` reverts the most recent not-undone batch of **that writer** (so a future agent's changes are never undone by Cmd-Z). It restores old values from the change log in a new batch with `op = 'undo'`, and marks the original batch `undone`.
- **Redo** re-applies the most recently undone batch of that writer, if no new change by that writer happened since (a new change clears the redo chain, like standard undo semantics). It is recorded with `redo_of`.
- Undo of a create tombstones the row (never a hard delete).
- **App integration:** the Edit menu's Undo/Redo (`CommandGroup(replacing: .undoRedo)`) send `undo`/`redo` to the agent. **While a text field has focus**, the standard text undo applies instead, so typing isn't undone through the store.
- **One save = one step:** the editor sends a single `updateTask` whose patch may also carry `tags` and `status`/`snoozedUntil`, so a save is one batch. (Found in manual check E1: separate commands made one save up to three undo steps.)
- **Feedback:** the store derives a label from a batch's change-log entries (`Create “…”`, `Delete “…”`, `Complete/Snooze/Drop/Reopen “…”`, `Edit “…” (title, due date, tags)`), using the item's current title. Undo/redo return it as `message`. The app shows it in a short centered overlay with a rewind/forward arrow, and the Edit menu items read "Undo <label>" / "Redo <label>" (observed from the store).

### L7: Calendar (app process)

- `EventSource` protocol in Core, with `EventKitSource` (real) and a fake for tests. Core sees plain value types (`CalendarInfo`, `Appointment`), never EventKit objects outside the adapter.
- **Day loading:** `predicateForEvents(withStart: dayStart, end: nextDayStart, calendars: visible)`, where day bounds come from `Calendar.current.dateInterval(of: .day, for:)`, which is DST-safe. Events overlapping the day are included, so ones spanning midnight appear on both days. All-day events are split out by `isAllDay`.
- **Cancelled** = `status == .canceled` or a title prefix `Canceled:` / `Abgesagt:` (case-insensitive). The prefix is shown stripped and the event struck through.
- **Live updates:** `EKEventStoreChanged` → reload the displayed day (debounced 300 ms). New calendars are visible by default.
- **Visibility:** a set of hidden `calendarIdentifier`s in the app's `UserDefaults`. That's acceptable for a Mac-only UI preference; device-local identifiers are a later concern (foundation D4 open point).
- **Refresh indicator:** EventKit exposes no per-account sync time. The app records, per source (account), the time of the last `EKEventStoreChanged` after which that source's events in a ±30-day window differed from the previous fingerprint (count + hash of keys and modification dates). Display: "SAP: 25 min ago", or "no changes since launch" until the first change. It also calls `refreshSourcesIfNecessary()` on launch and every 5 minutes. *Limitation:* this measures changes seen, not sync attempts. That's stated in the tooltip.
- **Permission:** `requestFullAccessToEvents` on first launch. The denied state shows a button opening `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`.

### L8: Day view composition

- Pure functions in Core build the view model: `DayModel(day, now, appointments, tasks)` → all-day list, timed list with `past/current/upcoming` state, task list (due that day, plus overdue if `day == today`, sorted per L3). They're unit-tested with fixed `now` values, including DST and midnight-spanning cases.
- **Time-based state** (past/current) refreshes via SwiftUI `TimelineView(.everyMinute)`. Crossing midnight while "today" is shown advances the view to the new day.
- **Keyboard:** ⌘← previous day, ⌘→ next day, ⌘T today, ⌘N new task (due on the displayed day when invoked from the day view).
- **Snoozed tasks:** queries treat `status = 'snoozed' AND snoozed_until <= today` as open, so the view is correct immediately. The app also sends `reconcileSnoozes(today)` on launch and at midnight to persist the transition (writer `system@<device id>`).
- **Snooze = "not now"** *(decided after manual check D7)*: the day view leaves snoozed tasks out until their snooze date (also when viewing future days; a later "peek into the future" will cover that). The task list keeps them at their normal position with an "until <day>" marker. The due date is not touched. `reconcileSnoozes` sets `status = open` and clears `snoozed_until`.

### L9: Testing strategy

- **Core unit tests** (`swift test`): migrations; each command's validation and logging; soft delete + undo/redo per writer; tag normalization, descendant filter, autocomplete, counts; task sorting; day task selection (due, overdue, snoozed); `DayModel` with a fake `EventSource` (all-day, overlap, midnight span, DST day, cancelled prefix).
- **Agent integration test:** the command handler runs in-process against a temporary database, called through an anonymous `NSXPCListener` endpoint, to exercise the XPC encoding without launchd.
- **Cross-process observation test:** the read-only pool + watcher sees a write from the read-write pool in another process (adapted from spike S4).
- **Manual check** (documented in tasks): real calendars, permission flows, login item approval, live update from Outlook.

## Risks / Trade-offs

- [The agent isn't approved/enabled as a login item → no writes] → A clear banner with a button to Login Items. Reading still works. `ping` on launch detects it.
- [Two processes request calendar access later (app now, agent in the MCP change)] → Accepted. Revisit in the MCP change: possibly the app gets schedule data from the agent instead.
- [The refresh indicator is approximate (changes seen, not sync attempts)] → Stated in the tooltip. Good enough to notice "nothing from SAP for 2 hours".
- [Floating due dates are ambiguous across time zone travel] → This is intended semantics for personal tasks. MCP will expose them as dates, not instants.
- [Text-field undo vs. store undo confusion] → Focus-based routing (L6). Verified manually.
- [UserDefaults keyed by `calendarIdentifier` breaks if the identifier changes] → A calendar would reappear as visible; low impact. Revisit with D4's calendar identity work.
- [The `v1` schema omits D3 tables (properties, links, recurrences, FTS)] → All are additive later; no column renames planned.

## Migration Plan

First release, no existing data. To reset during development: unregister the agent (app menu "Developer → Unregister agent"), quit, and delete `workdash.sqlite*` in the app group container. Rollback = delete the app; the store stays in the container.

## Open Questions

- Visual design details (timeline as a list vs. hour grid) can be decided while building the view without affecting the specs. Start with a list.
