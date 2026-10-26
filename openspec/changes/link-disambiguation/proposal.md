# Proposal

## Why

Pages may share a title: every person has a "Profile" and a "Goals" page, filed under `person/alex`, `person/sam` and so on. Pages and tasks, and pages and tags, also share names (the current store has examples of all three). Links already point to ids, so they never break, but WorkDash can't show *which* "Goals" a link means, the `[[` picker lists identical entries, and a typed `[[Goals]]` (from me or an agent) can never resolve. Duplicates should be normal, and everything should make them distinguishable.

## What Changes

- **Duplicate titles are allowed explicitly,** for pages and for tasks. Nothing is blocked or renamed.
- **Type icons on links:** in editor chips, the read view and the `[[` picker: a page icon, a task icon, a tag icon, a globe for web links, and a missing-page marker.
- **A live qualifier for duplicates:** where a title isn't unique among its kind, it's shown with the most specific tag that the other same-titled items don't have ("Goals · person/alex"), or the creation date if the tags don't differ. It's computed at display time from the current tags, never stored, and appears on chips, in the picker, ⌘K and search, backlinks and the tag page lists.
- **Picker entries get a second line:** kind, tags, last change.
- **Typed links get more precise:**
  - The prefixes `page:`, `task:` and `tag:` restrict the kind.
  - A tag path qualifies a title: `[[person/alex/Goals]]` is the page "Goals" tagged `person/alex` (tried only when no item has that exact title).
  - Combined forms like `[[page:person/alex/Goals]]` work too.
  - After resolution the link is a plain id link, so later tag changes don't matter.
- **Ambiguous typed links:** a `[[Goals]]` with several matches stays unresolved. The editor offers the candidates to pick one, and that pins the link to its id.
- **MCP:**
  - Unresolved links in responses list their candidates (id, kind, tags).
  - Links and backlinks in responses carry `display` (with the qualifier) and `tags`.
  - Tool descriptions explain the prefixes and the tag path.
  - `create_page` with a duplicate title succeeds and names the existing same-titled pages.

Not in this change: unique titles, merging duplicates, warnings for duplicate tasks.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `links`: how typed links resolve (prefixes, tag path, candidates for ambiguity), picker entries with kind and context, type icons and duplicate qualifiers on links.
- `info-pages`: page titles don't have to be unique.
- `agent-access`: agents get candidates for ambiguous links and `display` and `tags` on links; the syntax is documented in the tools.

## Impact

- **Core:**
  - `LinkResolver` parses prefixes and tag paths and returns candidates for ambiguous links.
  - A new `Disambiguation` helper computes qualifiers for a set of items with the same title (pure, testable).
  - `CommandOK.unresolved` gains candidates.
- **Editor library:**
  - Chips and the read view show the kind icon and the qualifier through the appearance callback (`LinkAppearance` gains kind and qualifier).
  - Missing links offer a candidate menu.
- **App:** picker rows, ⌘K, search, backlinks and tag page lists use the qualifier and the second line.
- **MCP:** response fields only. Existing fields stay compatible.
- **No schema change.**
