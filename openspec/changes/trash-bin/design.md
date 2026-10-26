# Design

## Context

- **Deleting** a page or task runs `Batch.softDelete("items", id)` in one change-log batch. It sets `items.deleted_at` and tombstones the item's live `item_tags` rows in the same batch. `live_*` views hide tombstoned rows; the derived link and search indexes follow the same writes.
- **Undo** reverts a batch (`revert(batch:)`: old values back, inserts tombstoned) and is per writer. The user can't undo an agent's delete (agent-access "User undo doesn't revert agent changes").
- **Writers** are `user@<device>`, `agent:<client>@<device>` and a system writer. `AgentActivity` already lists agent batches with labels.
- **Links to deleted targets** render as `LinkAppearance.deleted`. A click opens `workdash://item/<id>`, for which `WikiModel.destination(for:)` returns nil, so it beeps.
- **Missing links** use the shared native `MissingLinkMenu` (editor ⌘-click, read-view click; link-disambiguation K5).

Motivation and scope are in `proposal.md`, behavior in this change's specs.

## Goals / Non-Goals

**Goals:**
- **Restore reuses the change log:** it reverts the delete, so "exactly as it was" holds by construction, and no new storage is needed.
- **One link menu** for missing and deleted targets.

**Non-Goals:**
- Hard deletes, scrubbing history, retention jobs.
- Trash for tags or appointment notes (blocking overrides).
- Restoring several items at once.

## Decisions

### T1: Trash query from tombstones and the delete batch

`TrashQueries.list(db, since:)` returns items with `kind IN ('info','task') AND deleted_at IS NOT NULL`. For each, it takes the latest `change_log` entry with `op = 'delete'`, `table_name = 'items'`, `row_id = id` and not undone. That entry gives the batch (for restore), `at` (deleted when) and `writer` (deleted by).

**Tags** come from the `item_tags` rows tombstoned in that same batch: the tags the item had when it was deleted. Excerpt via `TreeLeaf.excerpt(of:)`.

**`since`** is now − 30 days; a count query feeds "Show older (n)". Rows without a delete entry (pre-history data) fall back to `deleted_at` and an unknown writer, and are still listed.

**Alternative considered:** a `trash` table written on delete. Rejected: it duplicates the change log, which already holds every fact the Trash needs.

### T2: Restore = revert the delete batch, as a new change

`Command.restore(id:)`:
1. Requires the item to be a deleted page or task, else `notFound` ("not in the trash").
2. Finds its delete batch (T1) and reverts only that batch's entries into a new batch of the current writer, through the same code as undo (`revert(batch:)`, factored to be callable for an arbitrary batch).
3. The new batch is a normal change (op `update`). So the restorer's ⌘Z deletes the item again, and redo works.

**Why revert, not "set `deleted_at = NULL`":** the delete batch also tombstoned the tag assignments, and reverting the batch restores exactly those. Assignments removed earlier stay removed.

**Undo label:** "Restore page “Goals”" / "Restore task …". In `label(ofBatch:)`, an items entry that sets `deleted_at` from a value back to NULL reads as a restore.

**Edge:** if the delete batch was already undone (item live), the item isn't in the trash, so restore fails with `notFound`.

### T3: Writer names

`WriterName.display(writer, me:)`:
- the current user writer is "you"
- `agent:claude-code@…` is "Claude Code"
- other `agent:<client>@…` show the client name as sent by the MCP client, with `-` turned into spaces and capitalized (e.g. Joule)
- the system writer is "WorkDash"

This lives in Core so the MCP tools can use it too.

### T4: App: Trash destination

- **Navigation:** `Navigation.Destination.trash` and a sidebar row "Trash" below Pages, with the 30-day count as a secondary number.
- **Layout:** a list on the left and a read-only preview on the right. The preview uses `WDMarkdownReadView` without `onChange`, so it is read-only, and its links can be followed.
- **Rows:** icon, title, tags, the excerpt line, and "deleted <relative> by <name>".
- **Restore:** a Restore button in the preview and a context menu on rows. After a restore, the undo overlay shows "Restore …", and the row leaves the list (observation).
- **"Show older (n)"** at the end of the list toggles the full list.

### T5: One link menu for missing and deleted targets

`MissingLinkMenu` becomes `LinkMenu`, built from an app-provided model:

```
LinkMenuModel
  replacements: [LinkSuggestion]   -> the editor replaces the link's range / the read view rewrites the link
  actions:      [(title, symbol, URL)]  -> opened through onOpenLink / openURL
```

- **Missing:** replacements = candidates; actions = new page and new task (`workdash://missing/…?create=`). This is today's behavior.
- **Deleted:**
  - action "Restore “…”" (`workdash://restore/<id>`), with "deleted … by …" in a disabled info item below it
  - replacements = live items of the same kind whose title equals the deleted title (`LinkResolver.candidates(db, typed: "page:" + title)`)
  - action "Show in Trash" (`workdash://trash/<id>`)

The editor passes a `linkMenu: (ParsedLink.Target) -> LinkMenuModel?` closure (replacing `candidates`). Deleted chips now open the menu on ⌘-click instead of `onOpenLink`.

**Read view:** a replacement rewrites the first link with that target via a generalized `MarkdownBlocks.pin(text, target:, with:)`, saved through `onChange`. One undo step either way.

`LinkOpener` handles the two new hosts: `restore` sends `Command.restore` and keeps the user where they are; `trash` navigates to the Trash with that item selected.

**Alternative considered:** the opener shows its own menu for deleted links. Rejected: relinking needs the link's range in the text, which only the editor and read view know.

### T6: MCP

- **`list_trash(all?: bool)`:** entries with `id`, `kind`, `title`, `tags`, `excerpt`, `deleted_at`, `deleted_by` (T3).
- **`restore(id)`:** returns the item like `get_page` / `get_task`.
- **Descriptions** say that deletes are recoverable and point agents to `restore` for mistakes. `get_page` / `get_task` on a deleted id keep returning not-found, with the hint "it is in the trash (restore)".

## Risks / Trade-offs

- **[The store grows forever]** → Personal scale: text pages and tasks are kilobytes. Revisit with sync, where tombstones are needed anyway.
- **[A deleted item's tags were changed in the batch before the delete]** → Restore only reverts the delete batch, so the item comes back as it was right before the delete, matching the spec.
- **[Deleted-link menu on a plain click in the read view, where a click used to do nothing]** → Intended: it's the recovery entry point. No data changes without choosing an entry.
- **[A same-titled relink target could be the wrong one]** → Entries show the qualifier ("Goals · person/alex"); one Undo reverts.

## Migration Plan

No schema change. Items deleted before this change appear in the Trash. Their writer and time come from the change log, which has existed since v1.
