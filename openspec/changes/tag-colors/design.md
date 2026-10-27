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

**Non-Goals:**
- Free colors (hex), per-item colors, theming.

## Decisions

### C1: Palette as names, in Core

`TagColor` is a `String` enum: `red, orange, yellow, green, teal, blue, indigo, purple, pink, brown, gray`.
- **Stored values:** the raw names, in a new nullable `tags.color` column (migration `v5`). The column is synced like the other tag fields.
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

## Risks / Trade-offs

- **[Automatic colors change for existing roots]** if the hash-to-palette mapping differs from today's SwiftUI-color mapping → The same 8 hues in the same order, so the colors stay the same.
- **[A user-chosen color makes a chip hard to read]** (yellow on light backgrounds) → System colors at 15% background opacity with text in the color. Yellow and gray get a darker text shade if needed during the manual check.
- **[Many observers]** → One observation in `TagColorModel`; chips only read a dictionary.

## Migration Plan

`v5`: `ALTER TABLE tags ADD COLUMN color TEXT`. Existing tags have no own color, so everything looks as today (automatic). There's no data migration. Rolling back to an older app ignores the column.
