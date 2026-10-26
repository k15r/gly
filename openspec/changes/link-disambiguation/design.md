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
- **Web links** written as `[text](url)` get a globe the same way. **Missing links** get no icon; their red style already sets them apart.

**Fallback,** if drawing proves fragile (caret, selection, scrolling): the icon only, with the qualifier in the chip's tooltip. That's a one-line change in the styler, and the spec is still met by the read view and lists.

**Read view:** simpler. `MarkdownBlocks.inline` builds the displayed `AttributedString`, so it prepends an SF Symbol image (`Image(systemName:)` via `Text` concatenation) and appends " · qualifier" in secondary style.

### K4: Picker, ⌘K, search, backlinks, tag pages

- **`SearchHit`** gains `tags` and `modifiedAt`, from a follow-up query by owner ids.
- **The app** formats the second line as "<Kind> · <tags> · edited <relative>".
- **Titles** everywhere use `DisplayNames`.
- **`LinkSuggestion`** already has `symbol`, `title` and `subtitle`; only the content changes.

### K5: The missing-link menu

One native `NSMenu` (`MissingLinkMenu`) serves both views; Esc or a click outside dismisses it. A first version used a SwiftUI `confirmationDialog` in the read view, which macOS shows as a sheet without Cancel; it was replaced.
- **Entries:** the candidates of an ambiguous link (`LinkResolver.candidates(db, typed:)`, read-only; icon, display name, tags in the tooltip), then "New page …" and "New task …" (K7). The menu always opens, also without candidates, so the user picks page or task.
- **Editor:** ⌘-click opens it at the link. A candidate replaces the typed range through the editor's `replace` (undo, session save).
- **Read view:** a click opens it at the pointer. A candidate rewrites the text in the view (`MarkdownBlocks.pin`) and saves it through `updatePage`, `updateTask` or `updateTagPage`, one undo step.
- **`Command.resolveLink`** does the same rewrite in Core. The app doesn't use it; it stays for agents and other clients that hold no text.
- **Creating:** the menu opens `workdash://missing/<text>?create=page|task`. The whole text is percent-encoded, `/` included; an earlier version kept `/` and lost the tag path.

### K7: Tag paths in the picker and new items from typed links

- **Picker:** the `[[` query is parsed like a typed link (prefix, tag path). Exact candidates come first, then title search on the part after the last `/`, kept to the allowed kinds and to items carrying the path's tag or one below it. Right after a `/`, `SearchQueries.underTag` lists the pages and open tasks under the tag (most recently changed first), then its subtags.
- **New item:** `LinkResolver.newItem(for:kind:)` turns `person/alex/Goals` into the title "Goals" with the tag `person/alex`, drops a matching prefix, and gives nil for the other kind's prefix or an empty title. So a link created from a tag path can't carry `/` in its title; the New Page sheet still allows that.
- **Picker entries for new items:** "New page …" inserts `[[title]]`, "New task …" inserts `[[task:title]]`. Nothing exists yet, so the prefix keeps the choice until the link is opened; the menu then offers only the new task.
- **Waiting links:** creating a task now resolves waiting links (`resolveMissing`), like creating a page; the tags are set first, so tag paths match.

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
