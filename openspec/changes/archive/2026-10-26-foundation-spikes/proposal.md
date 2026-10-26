# Proposal

## Why

WorkDash's requirements (vault: `Work/Projects/WorkDash/Requirements.md`, v2) rest on three technical assumptions that nobody has verified yet. If any of them is wrong, the data model and the process architecture are wrong, and both are expensive to change once real data exists. Before building the first usable feature (the day view with tasks on the Mac), we de-risk these assumptions with time-boxed spikes.

The Mac app comes first. The iPhone app and sync come later, but no decision made now may block them.

## What Changes

Three spikes. Each produces a **decision** (recorded in `design.md`) and throwaway code. No production feature ships in this change.

- **Spike 1: appointment identity (Mac).** Check whether `calendarItemExternalIdentifier` + `occurrenceDate` from EventKit is a stable key for SAP Exchange and private iCloud appointments: moved occurrences, title/attendee changes, series splits ("this and all following"), cancellations. Output: the key rule, plus how `cancelled` vs. `gone` is detected.
- **Spike 2: store on GRDB/SQLite.** Build the data model sketch (items, tags, links, typed properties, templates, recurrences, change log, tombstones) and fill it with realistic volume (~10k items). Check that the filter engine can compile to SQL, FTS5 full-text search, reactive SwiftUI updates through `ValueObservation`, and undo/history through the change log. Sketch on paper how the schema maps to `CKSyncEngine` later.
- **Spike 3: process model for the MCP server.** Check whether a stateless stdio shim can forward MCP calls over XPC to the WorkDash app (which owns the store, EventKit and later sync), and how the shim behaves when the app isn't running.

Decisions already made (from exploration, recorded in `design.md`):
- Store: GRDB/SQLite, with sync later through `CKSyncEngine`. SwiftData is ruled out.
- Code layout: `WorkDashCore` package without AppKit/UIKit, plus thin platform targets.
- Mac first. The iPhone comparison for appointment identity and the developer account / CloudKit are postponed.

## Capabilities

### New Capabilities

None. This change verifies technical assumptions and records decisions. It introduces no user-visible behavior. The capabilities (e.g. `day-view`, `tasks`, `calendar-annotations`, `tags-and-properties`, `mcp-server`) are specified in the follow-up change for the Mac day view.

### Modified Capabilities

None.

## Impact

- **Code:** throwaway spike code only (in a `spikes/` directory or separate branches). Not carried over into the product.
- **Dependencies evaluated:** GRDB (+ GRDBQuery for SwiftUI), SQLite FTS5, EventKit, XPC, an MCP SDK for Swift.
- **System:** EventKit permission on the SAP Mac. Xcode signing on a managed Mac must work (no paid developer account needed for local Mac development).
- **Follow-up:** the results feed the first feature change (Mac day view + tasks), and the decisions shape its specs and design.
- **Out of scope:** the iOS app, CloudKit/CKSyncEngine implementation, the markdown editor, title generation, Obsidian import, presentation mode.
