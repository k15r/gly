# Proposal

## Why

Tag chips are colored since the pages-list polish, but the color is computed from the top-level tag's name: arbitrary, it can collide between roots, and it can't be chosen. Color is a quick way to tell areas apart at a glance (people vs. projects vs. one important project), which only works if I pick the colors.

## What Changes

- **Any tag can have a color,** chosen from a small fixed palette that stays readable in light and dark mode. A group name without its own tag (like `person` above `person/alex`) can get one too.
- **Inheritance:** a tag without its own color uses the nearest color set above it (`person/alex/blargh` → `person/alex` → `person`). Without any, today's computed color stays the default.
- **Where colors show:** tag chips everywhere, a color dot on tag rows in the tag tree, and the tag page header.
- **Setting a color:**
  - a "Color" menu on the tag page and in the tag tree's context menu: palette entries plus "Automatic", which removes the tag's own color so it inherits again
  - each choice is one undo step
- **MCP:** `list_tags` and `get_tag_page` return each tag's color (own and effective), and agents can set or clear it.

Not in this change: custom colors outside the palette, colors for tasks or pages themselves.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `tags`: tag colors (own and inherited, the palette, the default) and setting them from the tag tree; the tag tree shows the color.
- `tag-pages`: the tag page shows the tag's color and lets the user change it.
- `agent-access`: tag colors in `list_tags` and `get_tag_page`; setting and clearing them.

## Impact

- **Store:** migration `v5` adds a nullable `color` column to `tags` (a synced table). New command `setTagColor(name:, color:)` that creates the tag row for a group name if needed, plus its undo label.
- **Core:** palette definition, effective-color resolution (own → nearest ancestor → computed default), and tag queries returning colors.
- **App:**
  - a shared tag-color lookup that observes the tags table and is used by `TagChip`
  - the tag tree dot, and the color menus on the tag page and in the tree
- **MCP:** fields in two tools, and a color parameter (set/clear) on `update_tag_page`.
