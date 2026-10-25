# Design

## Context

See `proposal.md` for the motivation. The requirements live in the vault (`Work/Projects/WorkDash/Requirements.md`, v2). Constraints relevant to this design:

- **Apple only, Mac first.** The iPhone app follows later and reuses the core. Sync between devices goes through the user's private iCloud database later.
- **SAP-managed Mac:** EventKit sees the SAP Exchange calendar (allowed by SAP). Apple Intelligence is restricted by MDM. No paid Apple Developer account yet; a free development team is enough for local signing, sandbox and app groups (Spike 3).
- **Data model from the requirements:** items (info, task, appointment note, local appointment), hierarchical tags with tag pages, typed links, typed properties with templates, recurring tasks (fixed / after completion / after appointment), inbox, change history.
- **Agents** connect through MCP and write the same data as the user.
- The repo is empty. There's no existing code to integrate with.

## Goals / Non-Goals

**Goals:**
- Lock in the decisions that are expensive to change later: storage engine, schema shape, appointment key, process model.
- Keep the iPhone + sync path open without building it.
- Each spike ends with a recorded decision (update this document) and clear exit criteria.

**Non-Goals:**
- Production-quality code. Spike code is thrown away.
- Building UI beyond what is needed to observe reactivity.
- Implementing CloudKit sync. Only the mapping is designed on paper.

## Decisions

### D1: Storage engine is GRDB/SQLite, sync later through CKSyncEngine (decided)

```
 Mac (now)                              iPhone (later)
 +---------------------+                +---------------------+
 | WorkDash agent (D5) |                | WorkDash iOS        |
 |  GRDB / SQLite      |                |  GRDB / SQLite      |
 |  change_log --------+--+          +--+-- change_log        |
 +---------------------+  |          |  +---------------------+
                          v          v
                     +--------------------+
                     | CKSyncEngine       |   (later)
                     | private iCloud DB  |
                     +--------------------+
```

- **Why:** the filter system (tag prefixes, typed properties, relative dates) and full-text search are core requirements. SQL plus FTS5 covers both directly. Conflict rules ("user beats agent") can be implemented exactly instead of relying on opaque last-writer-wins.
- **Alternative: SwiftData + automatic CloudKit mirroring.** Rejected. Predicates on to-many relationships are limited, there's no FTS, sync is a black box, and the user had a bad experience with it before.
- **Alternative: Core Data + NSPersistentCloudKitContainer.** More control than SwiftData, but the same CloudKit modelling restrictions and still no FTS.
- **Cost accepted:** writing the record mapping and change tracking ourselves when sync is introduced.

### D2: Sync-ready schema conventions from day one (decided)

Every synced table has:
- `id` UUID (never auto-increment)
- `created_at`, `modified_at`, `modified_by` (`user@<device>` | `agent:<name>`)
- `deleted_at` (tombstone, never a hard `DELETE` for user data)

All reads go through views or query helpers that exclude tombstones. Every write also appends to `change_log` (row, field, old, new, writer, timestamp). The change log serves three purposes: history in the UI, undo, and later the sync outbox.

### D3: Schema shape (decided, validated in Spike 2)

```
 +-----------------+       +------------------+       +-----------------+
 | items           |       | item_tags        |       | tags            |
 |-----------------|       |------------------|       |-----------------|
 | id              |<------| item_id          |   +-->| id              |
 | kind            |       | tag_id           |---+   | name "person/x" |
 | title, body(md) |       +------------------+       | color, archived |
 | task fields     |                                  | page_body (md)  |
 | event fields    |       +------------------+       +-----------------+
 | recurrence_id   |<------| links            |               ^
 +-----------------+       | from_id, to_id,  |               |
        ^                  | type             |       +-------+---------+
        |                  +------------------+       | templates       |
 +------+----------+                                  | prefix | tag_id |
 | recurrences     |       +------------------+       | -> keys         |
 | template, rule, |       | property_values  |       +-----------------+
 | model, missed-  |       | owner_id (item   |
 | policy          |       |   or tag)        |------>+-----------------+
 +-----------------+       | key_id           |       | property_keys   |
                           | text|num|date|   |       | id, name, type  |
                           | bool|ref         |       +-----------------+
                           +------------------+
                           +------------------+
                           | change_log       |
                           +------------------+
```

- **One `items` table for all kinds,** with nullable columns for each kind. Search, tags, links and properties work the same for every kind, and the filter engine targets one table. *Alternative:* a table per kind. Rejected because every cross-kind query becomes a union.
- **Tags are entities with UUIDs.** The name (with `/` hierarchy) is just a field, so renames never touch assignments. A prefix rename is a bulk update on names.
- **Tag assignments are rows of their own** (`item_tags`). Concurrent tagging on two devices merges per assignment. *Alternative:* a tag list on the item, which means fewer records but last-writer-wins for all tags.
- **Property values have typed columns.** Exactly one value column is set according to the key's type, so comparisons stay in SQL.
- **FTS5** as an external-content table over `items.title` + `items.body` (and `tags.page_body`), unicode61 tokenizer with diacritics removed, prefix queries.

**Spike 2 results** (evidence: `spikes/store-spike/FINDINGS.md`, all exit criteria met):

| Criterion | Result |
|---|---|
| Data set | 10k items, 501 tags, ~20k tag assignments, 50k property values, 5k links; generated in ~2 s |
| 4 filters correct, < 50 ms | Correct against an independent oracle; **2.6–15.7 ms** |
| FTS prefix (`budg*` → "Budgetfreigabe"), < 50 ms | **3.2 ms** (limit 50), 22 ms for all 8,687 hits; umlauts match without diacritics |
| SwiftUI list updates on external write | Yes, **~115 ms**, but only with the WAL watcher (below) |
| Delete → undo → history | Yes, the item comes back with its tags and properties |
| CKRecord mapping without schema blocker | See D3a. Only additive changes needed |

**Decisions confirmed:** a single `items` table, `item_tags` as rows of their own, typed property value columns, tombstones + `live_*` views, FTS5 external content with triggers.

**Changes and rules from the spike:**
- `change_log.batch`: groups one logical change (= one undo unit). Soft delete tombstones dependents (tag assignments, property values, links) in the same batch.
- **The filter engine compiles tag/property predicates to uncorrelated `i.id IN (SELECT …)` subqueries** and resolves property key IDs at compile time. A correlated `EXISTS` was ~100× slower (~1 s) on the EAV table.
- Uniqueness of tag/key names is enforced only among live rows (partial unique index). Incoming sync must handle collisions (see D3a).
- **Search results: items and tags as separate groups.** `bm25` scores from different FTS tables aren't comparable.
- **Inner parts of German compounds** ("freigabe" in "Budgetfreigabe") aren't found by the unicode61 tokenizer. Decide in the search change: accept, or add a trigram index.
- **GRDB doesn't observe writes from other processes.** Any database the app shows gets an `ExternalChangeWatcher` (DispatchSource on `-wal` → `notifyChanges(in: .fullDatabase)`). See D5.

### D3a: CloudKit mapping (paper, for the later sync change)

- **Private database, one custom zone** `WorkDash` (CKSyncEngine works with custom zones).
- **One `CKRecord` type per synced table** (`Item`, `Tag`, `ItemTag`, `Link`, `PropertyKey`, `PropertyValue`, `Template`, `Recurrence`). **Record name = row UUID.** Fields = columns.
- **References as plain string IDs**, not `CKRecord.Reference`. That avoids CloudKit cascade semantics and ordering constraints on save. Dangling references are tolerated; the UI shows "link target deleted".
- **Tombstones sync as a field** (`deleted_at`). CloudKit records are never deleted by normal user actions; physical deletion is a later compaction step.
- **Not synced:** `change_log` (local history/outbox), FTS tables (rebuilt by triggers), derived data.
- **Outbox:** unsynced `change_log` rows (`synced = 0`) → the set of changed record IDs for `CKSyncEngine.State.pendingRecordZoneChanges`.
- **Conflicts (`serverRecordChanged`), resolved per field:**
  1. Fields changed only on one side → take that side.
  2. Field changed on both sides → **user beats agent** (by the `modified_by` of each side's change); otherwise the newer `modified_at` wins.
  3. The losing value is written to the change log, so it stays visible in history.
  - Needs the last known server state per row → **additive column `ck_system_fields` (BLOB)** on each synced table, plus field-level knowledge of local unsynced changes (already in `change_log`).
- **Name collisions on incoming tags/property keys** (two devices created `person/alex`): the merge pass keeps the oldest, re-points `item_tags` / `property_values` to it, and tombstones the duplicate. Applying incoming records must not fail on the partial unique index; the merge runs in the same transaction.
- **Size:** markdown bodies stay well below the 1 MB record limit. No assets planned.
- **Schema blockers:** none. Needed additions are additive (`ck_system_fields`).

### D4: Appointment key (decided, verified on iCloud and SAP Exchange)

Evidence: `spikes/eventkit-probe/FINDINGS.md` (F1–F10). The original hypothesis (`externalId + occurrenceDate`) is **not sufficient**:
- The same occurrence can exist in several calendars (F1).
- Editing a single occurrence detaches it, appends `/RID=<original start>` to its external ID, and `occurrenceDate` follows the **new** start (F6).
- "All future events" creates a new series ID for the following occurrences (F7).
- Edits to one occurrence can change the key of another one (F8).

**Normalized key**

```
key = calendar + "/" + baseId + "@" + originalStart

baseId        = calendarItemExternalIdentifier without a "/RID=..." suffix
originalStart = RID value (seconds since 2001-01-01) if present,
                else occurrenceDate
calendar      = calendar identity (see open point below)
```

Verified on iCloud and Exchange: after moving, renaming and changing attendees of single occurrences, all normalized keys equal the keys from before the edits. `eventIdentifier` is never used (device-local, and shared by all occurrences of a series).

**Matching runs in two stages, and both are normal paths:**
1. Exact match on the normalized key.
2. Fuzzy match on the stored snapshot: same calendar, same day, similar title, organizer (Exchange). For series splits it also checks that the old series ends where a new series with the same title begins.

**Key migration:** on every `EKEventStoreChanged`, WorkDash re-resolves every annotated appointment. If stage 1 fails and stage 2 yields exactly one candidate, the stored key and snapshot are **updated**. If there are several candidates, the user decides. If there are none, the status becomes `gone`.

**Status detection:**
- `cancelled` = `status == .canceled` (organizer-cancelled meetings stay visible, F5). The title prefix `Canceled:` is the fallback.
- `gone` = no exact match and no fuzzy match (own deletions simply disappear, F9).

**Series tag rules:** a rule is bound to the series' base ID **plus** its title and organizer. When the series ends and a series with the same title/organizer starts at the next slot, the rule moves to the new series automatically. If that's ambiguous, WorkDash asks the user.

**Open point (deferrable):** a stable identity for the *calendar* part of the key across devices. `calendarIdentifier` may change on sync, and the title may be renamed. For the Mac-only phase, `source title + calendar title` with rename handling is enough. Revisit with the iOS target.

### D5: MCP process model (decided: option Y with a launch agent, validated in Spike 3)

Evidence: `spikes/mcp-spike/FINDINGS.md` (M1–M6). Verified end to end with a live call from Claude Code.

```
 Claude Code --stdio--> wd-mcp shim --XPC (Mach service)--> WorkDash agent
 (any MCP client)       stateless,        team-signed        launch agent in the app bundle,
                        not sandboxed     both directions    sandboxed, owns the store,
                                                             EventKit, later CloudKit sync
 WorkDash.app (UI) ------------------- XPC client ---------------^
```

- **The single writer is a launch agent** inside the app bundle, registered through `SMAppService.agent` (login item). A GUI app can't vend a fixed Mach service. A sandboxed agent may register a Mach name prefixed with its app group (`<TEAM>.dev.k15r.workdash.*`). Verified with a free development team, no provisioning profile.
- **The shim is stateless:** it translates MCP calls into XPC calls, with a 5 s timeout and a clear error ("agent not reachable → enable WorkDash in Login Items").
- **The agent is started on demand by launchd** (~100 ms). The UI app doesn't need to run for MCP.
- **Security:** both sides require the peer's code signature for our team (`setCodeSigningRequirement`).
- **The store lives in the app group container**, accessible to the app, the agent and (later) widgets.
- **MCP SDK:** the official Swift SDK (`modelcontextprotocol/swift-sdk`).
- **MCP payloads use local time with offset plus the time zone ID** (e.g. `2026-10-25T20:40:00+01:00`, `Europe/Berlin`), never bare UTC. The live test showed the calling agent otherwise has to convert itself (M6).
- **UI ↔ agent:** the UI is an XPC client of the agent for writes. Whether it also reads through XPC or opens the database read-only with the `ExternalChangeWatcher` (D3) is decided in the day-view change. Both work, and read-only + watcher is likely the simpler choice for reactive lists.
- *Option X (separate helper writing to the same database) was rejected:* multiple writers, cross-process change notification needed, and EventKit permission per binary.

### D6: Code layout (decided)

```
 WorkDashCore  (Swift package; Foundation + GRDB + EventKit only, no AppKit/UIKit)
   model, store, change log, filter engine, FTS, recurrence,
   tag/property logic, appointment matching, markdown -> attributes
        ^                          ^
        |                          |
 WorkDashMac (app bundle)      WorkDashiOS (later)
   WorkDash.app: SwiftUI UI      SwiftUI + UIKit bits, widgets
   WorkDashAgent: launch agent,
     store owner, XPC service (D5)
   wd-mcp: stateless MCP shim
   global hotkey
```

Rule: if logic in `WorkDashCore` needs `import AppKit`, it doesn't belong in Core. Markdown styling logic (parse → attribute runs) lives in Core, so the Mac (`NSTextView`) and iOS (`UITextView`) editors can share it.

## Risks / Trade-offs

- [Series splits and edits to other occurrences change keys (F7, F8: verified on iCloud)] → Normalized key + fuzzy matching + key migration on every calendar change. Series tag rules follow splits by title/organizer.
- [Exchange sync into Apple Calendar is slow (~20 min for new events during the initial sync on 2026-10-25; later edits arrived within minutes)] → The day view must show the last calendar refresh time per source. Check the account's refresh setting.
- [The ID differs on iOS (can't be verified now)] → Snapshot stored for every annotated appointment. Stage-2 matching exists from the start. Re-run Spike 1 on the iPhone as soon as an iOS target exists.
- [Writing our own CKSyncEngine sync is more work than automatic mirroring] → Conventions from D2 now. Sync is a separate, later change with its own design.
- [One `items` table gets wide/sparse as kinds grow] → Acceptable at personal scale. Revisit if a kind gains many specific columns.
- [EAV-style property values make complex filters slow] → Measured in Spike 2: fine (< 16 ms) with uncorrelated `IN` subqueries; correlated `EXISTS` was ~1 s. The filter engine must keep to set-based SQL.
- [Writes from another process don't update the UI (GRDB limitation, verified)] → `ExternalChangeWatcher` on the WAL file + `notifyChanges`. Prefer a single writer process (D5 option Y).
- [XPC between a stdio shim and a sandboxed app causes signing/entitlement friction on a managed Mac] → Verified in Spike 3: works with a free development team, app group-prefixed Mach name, launch agent via SMAppService.
- [The agent must be enabled as a login item; users can disable it] → The shim returns a clear MCP error, and the app shows the agent status and links to Login Items.
- [CloudKit needs a paid Apple Developer Program membership] → Not needed for the Mac phase (app groups and signing work with the free team). Decide on the membership before the iOS/sync change.
- [Spike code becomes product code] → Spikes live in `spikes/`. The follow-up change starts fresh in `WorkDashCore`.

## Open Questions

- Exact filter grammar (operators, relative date syntax, AND/OR precedence, negation): settled in the day-view/filter change. Spike 2 only needs a representative subset.
- Search for inner parts of German compounds (trigram index or not): settled in the search change (D3).
- Calendar identity part of the appointment key across devices: revisit with the iOS target (D4).
- UI reads via XPC vs. read-only database + watcher: settled in the day-view change (D5).
