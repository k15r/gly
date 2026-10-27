# Design

## Context

- **Tags** live in the synced `tags` table (`name`, `name_key`, `page_body`, sync columns). Group names like `person` have no row until something is written to them (`updateTagPage` and `createTag` create the row on demand).
- **Chip colors** come from `TagChip.tint(for:)` in the app: a hash of the top-level name picks one of 8 SwiftUI colors. There's no stored color.
- **Tag data** reaches the app through `TagQueries` and `TagPageQueries`, observed with GRDB, and reaches agents through `list_tags`, `get_tag_page` and `update_tag_page`.

Motivation is in `proposal.md`, behavior in this change's specs.

## Goals / Non-Goals

**Goals:**
- **Store only the user's choice:** colors are stored as palette names. Inheritance and defaults are computed at display time, so retagging and renaming need no repair.
- **One resolution rule,** in Core, used by app chips, the tree, tag pages and MCP.

- **Rename, merge and delete are single batches,** so undo is the usual change-log revert and there's no new history mechanism.

**Non-Goals:**
- Free colors (hex), per-item colors, theming.
- A separate tag-management window. Everything happens in the tag tree and on tag pages.
- Rename and delete over MCP.

## Decisions

### C1: Palette as names, in Core

`TagColor` is a `String` enum: `red, orange, yellow, green, teal, blue, indigo, purple, pink, brown, gray`.
- **Stored values:** the raw names, in the nullable `tags.color` column. The v1 schema already planned this column, but nothing has written to it, so every existing tag is "no own color". It's synced like the other tag fields.
- **Display:** the app maps names to SwiftUI system colors, which adapt to light and dark mode.
- **Unknown names** (an older app, or bad data) are treated as no color.

**Alternative considered:** storing hex values. Rejected: they don't adapt to dark mode, they invite unreadable choices, and agents would need to invent hex values.

### C2: Resolution (`TagColors`, pure)

`TagColors(own: [nameKey: TagColor])` is built from all live tags with a color.

`effective(for name) -> (color, source)`, where `source` is `.own`, `.inherited(fromName)` or `.automatic`:
1. Walk the path from the full key upwards (`person/alex/blargh`, `person/alex`, `person`); the first own color found wins.
2. If none is found, the automatic color for the top-level name: the same hash as today, moved into Core so MCP and the app agree. It maps to the palette names `blue, purple, teal, orange, pink, green, indigo, brown`, in that order.

The query that builds it is `TagQueries.colors(db)`: one `SELECT name_key, color FROM live_tags WHERE color IS NOT NULL`.

### C3: Command `setTagColor(name:, color: TagColor?)`

Creates the tag row if needed (as `updateTagPage` does, for group names), then sets or clears `color` through `Batch.update`: one undo step, attributed to the writer.

**Undo label:** "Color of tag “person”" (in `label(ofBatch:)`, when a tags entry changes only `color`).

### C4: App: one observed lookup, chips read it

- **`TagColorModel`** (`@Observable`) observes `TagQueries.colors` and exposes `effective(name)`. It's attached like the other models and put into the environment.
- **`TagChip.tint`** reads the model; the hash function moves to Core (C2).
- **Tag tree rows:** a small filled circle in the effective color before the segment name.
- **Context menu on tag rows:** a "Color" submenu with "Automatic", a separator, then the palette. Each entry has a colored circle image, and a `Toggle` gives the current own choice a native checkmark (lesson from planning: menus don't render `Label` images reliably, `Toggle`s render checkmarks).
- **Tag page header:** a color circle with the same menu, and a caption: "own color", "inherited from person" or "automatic".

### C5: MCP

- **`list_tags`:** entries gain `color` (own, or null) and `effective_color`.
- **`get_tag_page`:** gains the same two fields.
- **`update_tag_page`:** `text` becomes optional and `color` is new (a palette name, or `"automatic"` to clear). At least one of the two is required. An unknown name is rejected, with the allowed names listed in the error and in the tool description.

### C6: All tags in the tree

`TagQueries.tagTree` lists every live tag, including tags with nothing assigned and tags used only by finished tasks. So every tag can be colored, renamed or deleted from the tree.

A "Show unused tags" toggle was built first and removed after trying it: it hid tags you then couldn't find, and its effect was hard to see.

Clicking a tag row also expands it.

### C7: `Command.renameTag(from:, to:, merge: Bool)`

- **Validation:** `to` is a valid `TagName` and differs from `from` (case-only changes allowed: display casing).
- **Plan:** all live tags whose key equals `from` or starts with `from/` (the subtree), each mapped to the new name by swapping the prefix. A group name without its own row renames just its descendants.
- **No clashes:** update `name` and `name_key` of each row in one batch. Tag links in texts store the tag id, so they keep working; their labels are refreshed like item labels (`refreshLabels(tag:)`, via `link_index` with `target_kind = 'tag'`).
- **Clash** (any target key already exists as a live tag):
  - Without `merge: true`, the command fails with a `conflict` code that lists the clashing names. The app asks, then retries with `merge: true`.
  - With merge, for each clashing pair:
    1. Re-point the source's live assignments to the target. An item that already has the target just loses the source assignment.
    2. Append the source's description to the target's, separated by a blank line, if both have text.
    3. Rewrite tag links in texts from the source id to the target id, through `link_index` sources and the same rewrite as resolution.
    4. Keep the target's own color if set, else take the source's.
    5. Tombstone the source tag.
- **Undo label:** "Rename tag “person” to “people”" / "Merge tag “person/al” into “person/alex”".

**Alternative considered:** a new tag row per rename with redirects. Rejected: tag ids already make plain renames free, and merge is rare enough to pay for a text rewrite.

### C8: `Command.deleteTag(name:)`

- Tombstones the tag row (`softDelete`, which also tombstones its live `item_tags`). Subtags are untouched.
- Links to it render as deleted, through the existing appearance for tags.
- **Group name without a row:** nothing to delete, so the command fails with `notFound`. The UI only offers Delete on rows that are tags.
- **Count for the confirmation:** `TagQueries.usage(db, name:)` returns the number of live items carrying exactly this tag.
- **Undo label:** "Delete tag “project/old”".

### C9: UI for rename and delete

- **Context menu of tag rows:** New Subtag…, Color ▸, Rename…, Delete….
- **Tag page header:** a "…" menu with the same items.
- **Rename** opens an alert with a text field prefilled with the full name. On a `conflict` failure, a second alert says "Merge into “person/alex”?" and offers Merge or Cancel.
- **Delete** confirms with "Remove “project/old” from 3 items?" (or "Delete unused tag “…”?").
- **Navigation:** after a rename, a visible tag page navigates to the new name. After a delete, a visible tag page goes back.

## Risks / Trade-offs

- **[Merging touches many rows]** (assignments, texts) → One batch, so one undo restores everything. Text rewrites only touch sources listed in `link_index`.
- **[A rename into an existing subtree partially clashes]** (`person` → `people` where only `people/sam` exists) → The clash check covers the whole mapped subtree. The confirmation lists every pair that merges.

- **[Automatic colors change for existing roots]** if the hash-to-palette mapping differs from today's SwiftUI-color mapping → The same 8 hues in the same order, so the colors stay the same.
- **[A user-chosen color makes a chip hard to read]** (yellow on light backgrounds) → System colors at 15% background opacity with text in the color. Yellow and gray get a darker text shade if needed during the manual check.
- **[Many observers]** → One observation in `TagColorModel`; chips only read a dictionary.

## Migration Plan

No schema change: `tags.color` exists since v1 and is empty, so existing tags look as today (automatic). An older app ignores the column.
