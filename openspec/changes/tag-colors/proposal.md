# Proposal

## Why

Tag chips are colored since the pages-list polish, but the color is computed from the top-level tag's name: arbitrary, it can collide between roots, and it can't be chosen. Color is a quick way to tell areas apart at a glance (people vs. projects vs. one important project), which only works if I pick the colors. And tags can't be managed at all: a typo in a tag can't be renamed, two spellings of one tag can't be merged, and a tag nothing uses anymore is invisible, so it can't be changed or removed.

## What Changes

- **Any tag can have a color,** chosen from a small fixed palette that stays readable in light and dark mode. A group name without its own tag (like `person` above `person/alex`) can get one too.
- **Inheritance:** a tag without its own color uses the nearest color set above it (`person/alex/blargh` → `person/alex` → `person`). Without any, today's computed color stays the default.
- **Where colors show:** tag chips everywhere, a color dot on tag rows in the tag tree, and the tag page header.
- **Setting a color:**
  - a "Color" menu on the tag page and in the tag tree's context menu: palette entries plus "Automatic", which removes the tag's own color so it inherits again
  - each choice is one undo step
- **Unused tags become reachable:** a "Show unused tags" toggle in the tag tree also lists tags that only finished tasks use.
- **Rename a tag** from the tag tree's context menu or the tag page:
  - subtags are renamed along (`person/alex` → `people/alex` when renaming `person`)
  - links and labels follow
  - renaming onto an existing tag asks, then **merges**: the items of both end up under the existing tag, descriptions are joined, and links to the old tag point to the merged one
- **Delete a tag** from the same places, after a confirmation that says how many items use it. Those items lose the tag; subtags stay.
- **One undo step each:** every rename, merge and delete is a single undo step.
- **MCP:** `list_tags` and `get_tag_page` return each tag's color (own and effective), and agents can set or clear it.

Not in this change: custom colors outside the palette, colors for tasks or pages themselves, a separate tag-management window, renaming or deleting tags through MCP.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `tags`: tag colors (own and inherited, the palette, the default) and setting them from the tag tree; the tag tree shows the color; unused tags on demand; renaming, merging and deleting tags.
- `tag-pages`: the tag page shows the tag's color and lets the user change it, rename the tag and delete it.
- `agent-access`: tag colors in `list_tags` and `get_tag_page`; setting and clearing them.

## Impact

- **Store:** migration `v5` adds a nullable `color` column to `tags` (a synced table). New commands:
  - `setTagColor(name:, color:)`, which creates the tag row for a group name if needed
  - `renameTag(from:, to:)`, which renames the subtree and merges on a clash, rewriting tag links in texts
  - `deleteTag(name:)`, which tombstones the tag and its assignments

  Each gets an undo label.
- **Core:** palette definition, effective-color resolution (own → nearest ancestor → computed default), and tag queries returning colors.
- **App:**
  - a shared tag-color lookup that observes the tags table and is used by `TagChip`
  - the tag tree dot, and the color menus on the tag page and in the tree
- **MCP:** fields in two tools, and a color parameter (set/clear) on `update_tag_page`.
