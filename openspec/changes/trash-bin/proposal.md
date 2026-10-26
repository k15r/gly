# Proposal

## Why

Deleting a page or task only tombstones it, but WorkDash has no way to see or bring back what was deleted. Undo covers only my own most recent changes. Deletes by agents can't be undone from the app at all (undo is per writer), so when Claude Code or Joule removes the wrong duplicate, the item is effectively lost. And a link whose target was deleted is a dead end: clicking it only beeps.

## What Changes

- **Trash in the sidebar:** lists deleted pages and tasks, newest first. Each row shows kind, title, tags, the start of the text, when it was deleted and by whom (me, Claude Code, Joule, …). Selecting one shows a read-only preview.
- **Nothing is erased:**
  - Deleted items are kept for good.
  - The Trash shows the last 30 days by default; "Show older" lists the rest.
  - There is no "Delete permanently" and no "Empty trash".
- **Restore:**
  - brings an item back exactly as it was before the delete, including its tags
  - works for anyone's deletes, including agents'
  - is a normal change by whoever restores, so ⌘Z undoes it
  - makes links to the item work again
- **Broken links lead to recovery:** clicking a "link target deleted" link (⌘-click while editing) opens a menu:
  - **Restore "…"**, with when and by whom it was deleted
  - **Link to "…" instead**, for each live item of the same kind with the same title (re-points just this link; the duplicate case)
  - **Show in Trash**
- **MCP:** agents can list the trash and restore items, so an agent can fix its own wrong delete.

Not in this change: deleting tags, permanent deletion, a setting for the 30 days.

## Capabilities

### New Capabilities

- `trash`: the Trash view (contents, order, 30-day default view, preview) and restoring deleted pages and tasks.

### Modified Capabilities

- `links`: "Deleted link targets": a deleted target's link offers Restore, relinking to a same-titled item, and Show in Trash.
- `tasks`: "Delete a task": a deleted task is also recoverable from the Trash.
- `info-pages`: "Create, edit and delete pages": a deleted page is recoverable from the Trash.
- `agent-access`: new trash tools (list, restore); the tool list in "Tool descriptions guide agents" grows.

## Impact

- **Core (`WorkDashCore`):**
  - trash query, from deleted items plus the delete entry in `change_log` for when and by whom
  - a `restore` command that reverts the item's delete batch, and its undo label
  - candidates for relinking a deleted target
- **Editor (`WorkDashEditor`):** the link menu (today missing links only) also serves deleted targets: restore and show-in-trash actions, and relink replacements in editor and read view.
- **App:** Trash sidebar entry, list and preview; the link opener handles restore and show-in-trash.
- **MCP:** two tools and their descriptions.
- **No schema change, no migration.**
