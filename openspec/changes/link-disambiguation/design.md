# Design

## Context

- **Links** are stored canonically as `[label](workdash://item|tag/<uuid>)` (info-pages-and-links P1). The label is the title, refreshed on renames.
- **`LinkResolver`** turns a typed `[[Title]]` into a link when exactly one live page, task or tag matches the case-folded title. Otherwise it stays a missing link, and `CommandOK.unresolved` lists the titles.
- **The editor** (`WorkDashEditor`) styles links as chips through an `appearance` callback (`LinkAppearance.live(title:)` / `.deleted` / `.missing`). The read view renders inline markdown with `AttributedString`.
- **The picker, ⌘K and search** show `SearchHit`s (kind, title, excerpt). Backlinks show `LinkRef`s.

Motivation and scope are in `proposal.md`, behavior in the specs of this change.

## Goals / Non-Goals

**Goals:**
- **Identity stays the id;** everything new is about finding the right target and showing it.
- **One qualifier rule,** computed in Core and used by every surface (app and MCP).
- **No schema change.**

**Non-Goals:**
- Unique titles, merging duplicates, a kind preference order between pages, tasks and tags. Ties across kinds are ambiguous and are resolved by the prefix or the candidate menu.

## Decisions

### K1: Typed link grammar (`LinkResolver`)

```
[[ (page:|task:|tag:)? body ]]        prefix case-insensitive
```

1. **Exact match:** live items and tags of the allowed kinds whose case-folded title or name equals `body`.
2. **Tag path,** only if step 1 finds nothing and `body` contains `/`: split at the last `/` into `tagPath` and `title`. Then match live pages and tasks (allowed kinds, never tags) whose title equals `title` and that carry a tag whose key equals `tagPath`, or lies below it (the same descendant rule as the tag filter).
3. **Result:**
   - one match → canonical link
   - several → **ambiguous**: the link stays as typed, and the candidates are returned
   - none → missing

`resolve(text, db)` returns `(text, unresolved: [UnresolvedLink])`, where `UnresolvedLink` has the typed text and its candidates (`LinkRef` plus tags).

`CommandOK` gets an optional `unresolvedLinks: [UnresolvedLink]`; the existing `unresolved: [String]` stays for compatibility. Missing-link resolution on page creation (P3) uses the same function, so `[[person/alex/Goals]]` resolves when that page appears.

**Alternative considered:** `[[Goals @person/alex]]` or `[[Goals (person/alex)]]`. Rejected: the path reads like the tag tree, needs no new delimiter, and titles containing `/` keep working through step 1.

### K2: The qualifier (`Disambiguation`, pure)

`Disambiguation.qualifiers(_ items: [Item]) -> [id: String]`, where an `Item` has id, title, tags and createdAt, and all items share one kind and one case-folded title:
- **For each item:** its tags that no other item in the group carries. Pick the deepest one (most segments), with ties broken alphabetically.
- **If there's none:** "created <medium date>".
- **A group of one:** no qualifier.

`DisplayNames.display(db, refs:) -> [id: (display, tags)]` loads, for the referenced items, all live same-kind items with the same title in one query, groups them and applies the rule. **Scope:** pages among live pages, tasks among live tasks of any status. Tag names are unique already.

Results are computed on demand, never stored. The app caches them per observation cycle (they're recomputed when the store changes, because the queries that feed the views already observe `items` and `item_tags`).

### K3: Editor chips: icon and qualifier without touching the text

The stored text must stay `[Goals](workdash://item/…)`. So the icon and the qualifier are **drawn**, not inserted:
- `LinkAppearance.live` gains `kind` (page, task or tag) and `qualifier: String?`.
- `MarkdownAttributes` reserves room with **kerning** (`.kern`):
  - on the collapsed `[` before the label, the width of a small icon
  - on the last label character, the width of " · qualifier"

  Kerning adds space without adding characters.
- `WDTextView` overrides `drawBackground(in:)` / `draw(_:)`. For every chip range it gets the glyph rectangles from the layout (TextKit 2 `textLayoutManager` enumerate) and draws the SF Symbol in the reserved space before the label and the qualifier in secondary color after it.
- **Web links** get a globe the same way; **missing links** get a "+" doc icon.

**Fallback,** if drawing proves fragile (caret, selection, scrolling): the icon only, with the qualifier in the chip's tooltip. That's a one-line change in the styler, and the spec is still met by the read view and lists.

**Read view:** simpler. `MarkdownBlocks.inline` builds the displayed `AttributedString`, so it prepends an SF Symbol image (`Image(systemName:)` via `Text` concatenation) and appends " · qualifier" in secondary style.

### K4: Picker, ⌘K, search, backlinks, tag pages

- **`SearchHit`** gains `tags` and `modifiedAt`, from a follow-up query by owner ids.
- **The app** formats the second line as "<Kind> · <tags> · edited <relative>".
- **Titles** everywhere use `DisplayNames`.
- **`LinkSuggestion`** already has `symbol`, `title` and `subtitle`; only the content changes.

### K5: Choosing a candidate

- **Editor:** ⌘-click on a missing link calls `onOpenLink(workdash://missing/<text>)` as today. The app first asks Core for candidates (`LinkResolver.candidates(db, typed:)`, read-only). With candidates, it shows an `NSMenu` at the click: one entry per candidate (icon, display name, tags), then "Create page "…"". Choosing a candidate replaces the typed range with the canonical link through the editor's `replace`, so it gets undo and a session save. Without candidates, the behavior is unchanged: create the page.
- **Read view:** a click on a missing link with candidates opens the same choices as a SwiftUI menu or popover. Choosing one writes the text through `updatePage`, `updateTask` or `updateTagPage` (the typed range is rewritten in Core: `Command.resolveLink(source, typed:, target:)`).

### K6: MCP

- **Responses** add `unresolved_links: [{text, candidates: [{id, kind, title, display, tags}]}]`, next to `unresolved`.
- **`links` and `backlinks` entries** gain `display` and `tags`.
- **`create_page`** adds `same_title: [{id, display, tags}]` when other pages share the title.
- **Tool descriptions** explain `page:`, `task:`, `tag:` and `tag/path/Title`.

## Risks / Trade-offs

- **[Custom drawing in `NSTextView` (kerning plus overlay) misbehaves around selection, scrolling or wrapping]** → Contained in `WDTextView`, behind the fallback (icon only, qualifier in the tooltip).
- **[Tag-path resolution matches a tag below the path]** (`[[person/Goals]]` matches "Goals" under `person/alex` and `person/sam`) → That's ambiguous, so the candidates are offered. That's the intended way to find them.
- **[Qualifier churn while tags are being edited]** → It's display only, nothing is rewritten.
- **[Cost of computing display names for long backlink lists]** → One grouped query per view refresh; groups are small.

## Migration Plan

No data migration. Existing links are unchanged. Existing ambiguous `[[…]]` texts gain candidates the next time they're opened or saved.
