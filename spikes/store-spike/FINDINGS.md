# Spike 2 findings: GRDB/SQLite store

Package: `spikes/store-spike` (GRDB 7.11.1, system SQLite with FTS5, macOS 27, M4 Pro). Run `swift test` to reproduce. All numbers are best-of-5 after a warm-up, in-memory database.

## Data set (task 3.5)

Generated in **~1.6–2.0 s**: 10,000 items (50% task, 38% info, 9% event note, 3% local event, 3% tombstones), 501 tags (hierarchical `person/`, `project/…/…`, `topic/…`, flat), ~20k tag assignments, 20 typed property keys, 50,000 property values (10% on tags), 5,000 links, 50 recurrences.

## S1: Schema with D2 conventions holds (tasks 3.2–3.4)

- Every synced table has `id` (UUID text), `created_at`, `modified_at`, `modified_by`, `deleted_at`. Reads go through `live_<table>` views.
- Unique tag/key names are enforced **only among live rows** (partial unique index). With sync later, duplicates can still arrive from two devices and need a merge pass (as expected from D2).
- CHECK constraints guard the enums (kind, status, priority, recurrence model, missed policy).
- **Change log:** per-field old/new values, writer, `batch` (one logical change = one undo unit). Soft delete cascades tombstones to dependents (tag assignments, property values, links) **in the same batch**, so a single undo restores an item with its tags and properties. Undoing an insert tombstones the row; nothing is ever hard-deleted.
- Added a `batch` column to `change_log` (not in the D3 sketch) to group a logical change.

## S2: Filter → SQL works, but only with uncorrelated subqueries (task 3.6)

| Filter | Rows | Time |
|---|---|---|
| `task AND status = open AND priority >= high` | 581 | 2.6 ms |
| `task AND (1-1 OR person/*) AND NOT status = done AND due < today` | 503 | 15.7 ms |
| `person/* AND next_review < +30d` | 532 | 12.1 ms |
| `tag:project AND effort > 50` | 416 | 11.1 ms |

- Results are checked against an **independent in-memory oracle**: identical sets for all four.
- **First version was ~1,000 ms** for property filters. A correlated `EXISTS (… WHERE pv.owner_id = i.id AND k.name = ? AND pv.date_value < ?)` made SQLite pick the `(key_id, date_value)` index and rescan all matching values **per item**.
- **Fix:** compile tag and property predicates to **uncorrelated `i.id IN (SELECT owner_id …)`** subqueries, and resolve property key IDs at compile time. ~100× faster, and the plan uses `LIST SUBQUERY` + bloom filter.
- → Rule for the real filter engine: **set-based subqueries, never correlated per-row lookups** on EAV tables.
- Priority comparisons (`>= high`) work via a rank mapping. Relative dates (`+30d`, `today`) are resolved at compile time against "now".

## S3: FTS5 (task 3.7)

| Query | Time |
|---|---|
| `budg*` (limit 50) | 3.2 ms |
| `budg*` (all 8,687 hits) | 22.3 ms |
| `Prufung` / `Prüfung` | 2.5 ms (identical results) |
| `Seite` (tag pages) | 0.4 ms |

- External-content FTS5 tables for items (title, body) and tags (name, page body), kept in sync by triggers. `unicode61 remove_diacritics 2` makes umlauts match without diacritics. Prefix indexes `2 3 4`.
- Updates move entries in the index; tombstones are excluded at query time; undo brings them back (tested).
- Views don't expose `rowid`, so FTS joins must go to the base table + `deleted_at IS NULL`.
- **Ranking across tables is not comparable:** `bm25` from `items_fts` and `tags_fts` uses different corpus statistics, so merging by score ranks tags oddly. → Show items and tags as **separate result groups**, or use one unified FTS table over all searchable content.
- German compounds work for **prefix** queries (`budg*` → "Budgetfreigabe"), not for inner parts ("freigabe" doesn't find "Budgetfreigabe"). Needs a decision later (trigram tokenizer as a second index?).

## S4: Reactive UI and writes from other processes (task 3.8)

- `ValueObservation` drives a SwiftUI list (`StoreSpikeUI`) and updates on in-process writes.
- **GRDB does NOT observe writes from other processes.** A row inserted by the `sqlite3` CLI is in the database, but the observation never fires (tested).
- **Fix:** watch the `-wal` file with a `DispatchSource` and call `db.notifyChanges(in: .fullDatabase)`. The observation then fires **~70–115 ms** after the external write (tested headless and in the window).
- → Relevant for **D5**: with option Y (the app is the only writer) this isn't needed for MCP. With option X (separate helper writing), the watcher is mandatory. Either way, the watcher is cheap insurance against any external writer (scripts, a future sync process).
- Cosmetic: SwiftUI `List` logs "reentrant operation in its NSTableView delegate" on the first update. Harmless for the spike.

## Pending

- 3.9: paper mapping of tables → `CKRecord` and conflict rule.
- 3.10: final schema decisions into design.md D3.
