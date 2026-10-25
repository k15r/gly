# Tasks

## 1. Setup

- [x] 1.1 Install Xcode (only Command Line Tools are present today) and select it with `xcode-select`; verify `xcodebuild -version` prints a version on the SAP Mac
- [x] 1.2 Verify local code signing works on the managed Mac with a free personal team: build and launch an empty sandboxed SwiftUI macOS app from Xcode and confirm it starts without Gatekeeper/MDM blocks
- [x] 1.3 Create `spikes/` with a short `spikes/README.md` stating that all code there is throwaway and must not be reused in `WorkDashCore`; verify the file exists

## 2. Spike 1: Appointment identity (D4)

- [x] 2.1 Build a command-line EventKit probe in `spikes/eventkit-probe` (Info.plist with calendar usage description embedded) that lists events for a date range with `calendarItemExternalIdentifier`, `eventIdentifier`, `occurrenceDate`, `startDate`, `status`, title, organizer, calendar; verify it prints SAP Exchange and private iCloud events after granting calendar access
- [x] 2.2 Add a snapshot mode that writes the probe output to JSON and a diff mode that compares two snapshots by key; verify a diff of two runs without calendar changes reports zero differences
- [x] 2.3 Verify that all occurrences of one recurring SAP series (e.g. a 1:1) share the same `calendarItemExternalIdentifier` and differ in `occurrenceDate`; record the result in `spikes/eventkit-probe/FINDINGS.md`
- [x] 2.4 Verify behaviour for a moved single occurrence, a title change and an attendee change (use a test series organized by yourself); record in FINDINGS.md whether key and `occurrenceDate` stay stable
- [x] 2.5 Verify behaviour for a "this and all following" edit on a self-organized test series; record in FINDINGS.md whether the series splits into a new identifier
- [x] 2.6 Verify how a cancelled meeting appears (`status == .canceled`, "Canceled:" title prefix, or disappearance) for both a self-cancelled and an organizer-cancelled meeting; record the detection rule in FINDINGS.md
- [x] 2.7 Repeat 2.3 and 2.4 for a private iCloud calendar; record in FINDINGS.md
- [x] 2.8 Write the final key rule, the `cancelled`/`gone` detection rule and the series-split strategy into design.md D4 (status: decided); verify design.md D4 no longer says "hypothesis"

## 3. Spike 2: GRDB store and schema (D2, D3)

- [x] 3.1 Create a Swift package in `spikes/store-spike` with GRDB as a dependency; verify `swift build` succeeds
- [x] 3.2 Implement the D3 schema as GRDB migrations with the D2 conventions (UUID ids, timestamps, `modified_by`, `deleted_at`) and tombstone-excluding views; verify with a test that migrating an empty database creates all tables and views
- [x] 3.3 Implement the change-log write path (every insert/update/soft-delete appends a `change_log` row); verify with tests that update and delete produce the expected log entries
- [x] 3.4 Implement undo of the last change from the change log; verify with a test that delete → undo restores the item with its tags and properties
- [x] 3.5 Write a data generator (~10k items of all kinds, ~500 hierarchical tags, ~50k typed property values, links, recurrences); verify the generated database has the expected row counts
- [x] 3.6 Implement a minimal filter parser and SQL compiler for: tag prefix (`person/*`), tag AND tag, built-in field comparison (`status = open`), typed property comparison incl. relative date (`next_review < +30d`); verify with tests against the generated data that results are correct and each query takes < 50 ms
- [x] 3.7 Add an FTS5 external-content index over item title/body and tag page bodies (unicode61, diacritics removed, kept in sync by triggers); verify with tests that `budg*` finds "Budgetfreigabe", umlauts match without diacritics, and queries take < 50 ms on the generated data
- [x] 3.8 Build a minimal SwiftUI window bound to a tag-filtered item list through `ValueObservation`; verify that a write from a second process (e.g. `sqlite3` CLI or a test script) updates the list without manual refresh
- [x] 3.9 Write the paper mapping of tables to `CKRecord` types and the conflict rule ("user beats agent", per-record vs per-field) as a section in design.md; verify the section names every synced table and lists any schema blockers found (or states none)
- [x] 3.10 Record measured timings, problems and the final schema decisions (single `items` table, `item_tags` rows, typed property columns: kept or changed) in design.md D3 (status: decided); verify D3 no longer says "hypothesis"

## 4. Spike 3: MCP process model (D5)

- [x] 4.1 Create a sandboxed macOS app target in `spikes/mcp-spike` that exposes an XPC service (Mach service via launch agent / login item) answering a `getSchedule(date)` call with stub data; verify with a small XPC client that the call returns data
- [x] 4.2 Create a stdio MCP shim (choose official Swift MCP SDK or hand-written JSON-RPC and note why) that maps an MCP `get_schedule` tool to the XPC call; verify via the MCP inspector or a raw JSON-RPC request over stdin that `tools/list` and `tools/call get_schedule` work
- [x] 4.3 Register the shim in Claude Code (`claude mcp add`) and verify Claude Code can call `get_schedule` and receives the stub data
- [x] 4.4 Verify behaviour when the app is not running: the shim either triggers launch through the launch agent / login item or returns a clear MCP error; document which works
- [x] 4.5 Replace the stub with a real read from the Spike 2 database inside the app process; verify Claude Code receives real items
- [x] 4.6 Record the decision (option Y kept or fallback to X), the chosen MCP SDK and signing/entitlement findings in design.md D5 (status: decided); verify D5 no longer says "hypothesis"

## 5. Wrap-up

- [x] 5.1 Review design.md end to end: all of D3, D4 and D5 marked decided, risks updated with what the spikes revealed, open questions still deferrable; verify `openspec validate foundation-spikes` passes
- [x] 5.2 Update the vault `Requirements.md` where spike results change requirements (e.g. appointment matching, process model); verify the changed sections reference this change

## Workflow follow-up

- Start the follow-up change for the Mac day view + tasks (`/opsx:propose`) using the decisions in design.md.
- Archive `foundation-spikes` after the follow-up change has picked up the decisions.
