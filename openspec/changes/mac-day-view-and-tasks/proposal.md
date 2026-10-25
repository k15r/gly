# Proposal

## Why

WorkDash is meant to be the one place I look at to see my day. The foundation spikes (`foundation-spikes`) confirmed the technical approach on the SAP Mac: EventKit sees SAP Exchange and private calendars, a GRDB/SQLite store is fast enough, and a launch agent can own that store. Nothing usable exists yet, though. This change ships the first daily-usable slice on the Mac: today's appointments from all calendars plus my own tasks, in one window.

## What Changes

- **New Mac app** `WorkDash.app` with a **day view**: the appointments of one day from all EventKit calendars (SAP Exchange, iCloud, subscribed), read-only, merged into one timeline, with day navigation and a per-source "last refreshed" indicator. Tasks due that day (and overdue ones) are shown alongside, sorted by priority.
- **Calendar sources:** list the system calendars, show or hide each one, use their colors, handle calendar permission (not determined / denied / granted), and update live when the system calendar changes. Cancelled appointments stay visible and are marked as cancelled.
- **Tasks:** create, edit, complete, reopen, snooze, drop and delete tasks with title, notes (plain markdown text for now), status, priority (`none` · `low` · `normal` · `high` · `urgent`), optional due date and tags. A task list shows all open tasks and can be filtered by tag. The last change can be undone.
- **Tags (basic):** free hierarchical tag names (`person/alex`, `project/atlas`). Assign them to tasks with autocomplete. A tag filter includes everything below it.
- **Foundation that later changes build on** (production code, not spike code):
  - `WorkDashCore` Swift package: schema and migrations following the spike conventions, change log with undo, task/tag logic.
  - `WorkDashAgent`: launch agent that owns the store and accepts writes over XPC.
  - The app reads the store directly (read-only) and updates live when the agent writes.

Not in this change: MCP tools, info/notes items, appointment annotations, tag pages, properties, saved views/filter language, full-text search, recurring tasks, the inbox, local appointments, global hotkey, iOS and sync.

## Capabilities

### New Capabilities

- `calendar-sources`: reading appointments from the system calendars (EventKit), calendar visibility and colors, permission handling, live updates, cancelled status, refresh indicator.
- `day-view`: the day screen. Merged appointment timeline, all-day appointments, day navigation, tasks due/overdue for the day, staleness display.
- `tasks`: task lifecycle and fields (status, priority, due date, snooze, notes), task list with sorting and tag filter, undo, persistence and change history.
- `tags`: hierarchical tag names, assigning tags to tasks, autocomplete, filtering by tag including descendants.

### Modified Capabilities

None (no existing specs).

## Impact

- **New code:** `WorkDashCore` (Swift package), `WorkDash.app` (SwiftUI, macOS 14+), `WorkDashAgent` (launch agent, XPC service). The Xcode project is generated with XcodeGen from `project.yml` at the repository root.
- **Dependencies:** GRDB 7.x. EventKit, ServiceManagement, XPC (system).
- **System:** calendar permission for the app. The agent is registered as a login item. The store lives in the app group container `DB33H6YGK7.dev.k15r.workdash`. Signing uses the free development team `DB33H6YGK7`.
- **Spikes:** code in `spikes/` is not reused. Only the decisions and the proven techniques from `foundation-spikes/design.md` are.
