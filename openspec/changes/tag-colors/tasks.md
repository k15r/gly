# Tasks

## 1. Core

- [x] 1.1 Use the existing `tags.color` column (v1, unused so far; no migration), add the `TagColor` palette, `TagColors` resolution with automatic fallback (C1, C2) and `TagQueries.colors`; verify with tests for "Color a group", "Override below", "No colors set" (same automatic color as today's mapping for a few roots), unknown stored names treated as none, and existing tags without own color
- [x] 1.2 Add `Command.setTagColor(name:, color:)` (C3) creating group tag rows on demand, with the undo label; verify with tests for setting, clearing ("Back to automatic" incl. one undo), a group name without a row, and that the description stays untouched
- [x] 1.3 Add `renameTag(from:, to:, merge:)` (C7) with subtree rename, label refresh, conflict failure listing clashes, and merge (assignments, descriptions, link rewrite, color, tombstone), plus `deleteTag(name:)` and `TagQueries.usage` (C8) and `tagTree(includeUnused:)` (C6); verify with tests for "Rename a group", "Fix a typo" (one undo), "Merge two spellings" (incl. an item carrying both tags, joined descriptions, rewritten link, one undo), a partial subtree clash, "Delete a used tag" (one undo restores all assignments), a group name without row, and "Tag of finished work"

## 2. MCP

- [ ] 2.1 Add `color` / `effective_color` to `list_tags` and `get_tag_page`, and `color` (palette name or `automatic`) to `update_tag_page` with optional `text` (C5); verify with MCP tests for "Tags below a prefix" (colors present), "Agent colors a tag", clearing, and an unknown color name rejected with the allowed list

## 3. App

- [ ] 3.1 Add `TagColorModel` and make `TagChip` use effective colors; dot on tag tree rows; "Color" submenu in the tree's context menu and on the tag page header with own/inherited/automatic caption (C4); verify manually "Color a group", "Override below", "Back to automatic", "Inherited color shown", readability of all palette colors in light and dark mode
- [ ] 3.2 Add Rename…, Delete… and Show Unused Tags to the tree's context menu and a "…" menu on the tag page (C9): rename alert, merge confirmation on conflict, delete confirmation with the item count, navigation after rename/delete, unused tags marked; verify manually "Rename a group", "Merge two spellings", "Merge declined", "Delete a used tag", "Tag of finished work", "Rename from the tag page"

## 4. End to end

- [ ] 4.1 Manual checks in `docs/manual-checks-tag-colors.md` (neutral test data): the color and tag-management scenarios above in the app, colors surviving a restart, rename/merge/delete each undone with one ⌘Z, and Claude Code setting `project/atlas` to orange via `update_tag_page` and reading it back with `list_tags`

## Workflow follow-up

- Run `/opsx:verify tag-colors`, then archive after the manual checks pass.
