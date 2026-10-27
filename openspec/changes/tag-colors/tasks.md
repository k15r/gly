# Tasks

## 1. Core

- [ ] 1.1 Add migration `v5` (`tags.color`), `TagColor` palette, `TagColors` resolution with automatic fallback (C1, C2) and `TagQueries.colors`; verify with tests for "Color a group", "Override below", "No colors set" (same automatic color as today's mapping for a few roots), unknown stored names treated as none, and the migration on an existing v4 store
- [ ] 1.2 Add `Command.setTagColor(name:, color:)` (C3) creating group tag rows on demand, with the undo label; verify with tests for setting, clearing ("Back to automatic" incl. one undo), a group name without a row, and that the description stays untouched

## 2. MCP

- [ ] 2.1 Add `color` / `effective_color` to `list_tags` and `get_tag_page`, and `color` (palette name or `automatic`) to `update_tag_page` with optional `text` (C5); verify with MCP tests for "Tags below a prefix" (colors present), "Agent colors a tag", clearing, and an unknown color name rejected with the allowed list

## 3. App

- [ ] 3.1 Add `TagColorModel` and make `TagChip` use effective colors; dot on tag tree rows; "Color" submenu in the tree's context menu and on the tag page header with own/inherited/automatic caption (C4); verify manually "Color a group", "Override below", "Back to automatic", "Inherited color shown", readability of all palette colors in light and dark mode

## 4. End to end

- [ ] 4.1 Manual checks in `docs/manual-checks-tag-colors.md` (neutral test data): the scenarios above in the app, colors surviving a restart, and Claude Code setting `project/atlas` to orange via `update_tag_page` and reading it back with `list_tags`

## Workflow follow-up

- Run `/opsx:verify tag-colors`, then archive after the manual checks pass.
