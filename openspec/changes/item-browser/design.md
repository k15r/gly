# Design

## Context

- **Items** (`live_items`): `kind` is `task`, `info` (pages), `event_note` (meetings) or `bookmark`. Tags are rows in `item_tags`. The full-text index is `search_index` (FTS5, title + text, with a `kind` column). Tag filters with descendants are `TagFilter` (SQL fragment, segment-exact).
- **Today's list sources:**
  - `TaskQueries.taskList(mode:tag:)`, with `openOrderSQL`
  - `PageQueries.list(tag:)`
  - `BookmarkQueries.list(tag:text:)`
  - `TagPageQueries.page`
  - `TagQueries.tagTree` (open-task counts, item leaves from `leavesByTag`/`untaggedItems`)
- **UI:**
  - `TaskListView` (Open/Done/Dropped, tag chip, New Task) and `PagesListView`, `BookmarksListView`, `TagPageView`.
  - `TagTreeView` with `TreeLeafRow`; `treeRow`/`TreeDropState`/`ItemMove` handle drag and drop.
  - Navigation destinations: `.tasks`, `.pages`, `.bookmarks`, `.tag(name)`.
- Observation goes through `Live`/`ValueObservation` on the read-only store; writes go to the agent.

## Goals / Non-Goals

**Goals:**
- One query model shared by every list, the tag tree counts and the refine row, so all of them agree.
- The query is plain data (parseable from and printable to text), so saved views, ⌘K "Show all results" and a later MCP tool use the same thing.

**Non-Goals:**
- Syncing saved views; boolean OR between filters; nested queries.
- Changing the Day view or the item pages.
- An MCP `list_items` tool (follow-up; the query type is ready for it).

## Decisions

### I1: `ItemQuery`: data, text form, SQL

`ItemQuery` (GlyCore, `Browse/`) is a struct:
- `kinds: Set<ItemKind>`
- `tags`, all must match, each including descendants
- `excludedTags`
- `untagged`
- `statuses: Set<TaskStatus>` (applies to tasks only; other kinds pass)
- `due: DueFilter?` (overdue, today, week, none)
- `priorities`, `efforts`
- `changed: ChangedFilter?` (today, 7d, 30d)
- `author: Author?` (me = not `agent:%`, agent)
- `hosts`
- `text`

`ItemQuery.parse(_:)` reads the token syntax of the spec; unknown `key:value` and plain words become text. `description` prints the canonical form. Both are covered by round-trip tests.

`BrowseQueries.items(db, query, today:, limit:)` builds one SQL over `live_items i`:
- AND-ed conditions, one `TagFilter` per tag, `NOT (…)` for exclusions, `NOT EXISTS item_tags` for untagged.
- The text goes through `search_index MATCH` (via `SearchQueries.ftsQuery`) as `i.id IN (SELECT owner_id …)`, with the bm25 rank kept for relevance sorting.
- Meetings count only with notes (`body != ''`), as today.

It returns `[BrowseItem]`:
- id, kind, title, excerpt, tags, modified/created/completed dates, `modified_by`
- for bookmarks the URL
- for tasks the `TaskItem`, so rows reuse `TaskRow`

- **Alternative: filter in memory over all items.** Rejected: the text search needs FTS anyway, and SQL keeps the 5,000-item budget easy.
- **Alternative: one query type per kind.** Rejected: that's today's state, and the source of the inconsistency.

### I2: Facets from the same results

`BrowseFacets.of(results)` counts, per tag path including ancestors, how many results carry it or a tag below it. It's computed in memory from the results' tag lists (no second query), so the refine row and the result count can't disagree.

The tag tree's counts use the view's query **without its tag filters** (`query.droppingTags()`). Otherwise every tag outside the filter would show 0 while you filter. That's one extra query per view change, observed like the results.

### I3: Views

`ItemView { id, name, symbol, query, group, sort, builtIn }`.
- **Presets:** All items, Tasks (`is:task status:open status:snoozed`, task order), Pages (`is:page`, last change), Bookmarks (`is:bookmark`, title), Meetings (`is:meeting`, last change).
- **Saved views:** stored as JSON in `UserDefaults` (per Mac), with the query in its text form, so older builds and later changes of the struct don't break them.
- **Navigation:** `.items(viewID)` replaces `.tasks`, `.pages` and `.bookmarks`; `.tag(name)` shows the browser with a tag header. A `BrowserModel` keeps the edited query per view while the app runs; "Reset" goes back to the preset.

### I4: Filter bar

A token field:
- Chips for each filter (✕ to remove), then a text field.
- Typing a complete token and space or Return turns it into a chip. `#` suggests existing tags (the same tree as `TagField`), and `is:` / `status:` / `due:` suggest their values.
- A "+" menu offers each filter kind with its values.

The bar edits the view's `ItemQuery` and never a string, so chips and text stay in sync.

### I5: Refine row, grouping, sorting

- **Refine row:** up to 8 tags from the facets, leaving out tags in the filter and their ancestors, most frequent first. A click adds `#tag`.
- **Group and sort:** menus in the toolbar. Grouping is done in memory on the results:
  - **kind:** in tag views, with "Finished tasks" as its own collapsed group
  - **due:** overdue / today / this week / later / none, based on the local day
  - **status**
  - **tag:** next level under the filtered tag, else the top level; an item with two tags appears in both groups
- **Sorting** uses SQL `ORDER BY`. Task-list order is `openOrderSQL`, and done tasks sort by completion.

### I6: Rows and opening

- `ItemRow` uses `TaskRow` for tasks (status bar, chips, hover actions); other kinds get a generic row in the same layout (icon, title, excerpt, chips, trailing host/date).
- `ItemOpen.click(item, nav)`: ⌘ held and the item has a URL (bookmark) → `NSWorkspace.open`, otherwise its page. Used by rows, tag views and quick open, replacing `BookmarkOpen.click`.
- The drag payload stays `kind\nid\nsourceTag`, with `sourceTag` = the view's only tag filter (if exactly one), so `ItemMove` keeps its move/alias semantics.

### I7: Tag tree

- `TagTreeView` loses its leaves (`TreeLeafRow`, `untaggedItems`), and gains a filter field (case-insensitive substring on the full path; matches keep their parents and are expanded) and view-relative counts (I2).
- **Click:** in a browser view (not a tag view) it sets the view's tag filter to this tag; ⇧-click adds or removes it; ⌘-click opens the tag view, as does any click outside a browser view. A click also expands the tag. (Tried "click opens the tag page" in between; filtering the view you're in is what a click on a tag is for.)
- **Tag chips in rows:** `TagChipLine` shows as many chips as fit on one line and "+N" with the rest in a hover popup (`ViewThatFits` over the prefixes; a plain tooltip does not show inside rows with their own hover and tap handling), replacing a wrapping layout that clipped tags when the row's width wasn't known yet.
- **Context menu:** "Open Tag Page" plus the existing color/rename/delete/new subtag.
- "Untagged" sets `untagged`.

### I8: Tag view

`.tag(name)` renders `ItemBrowserView` with the query `#name`, grouped by kind. The header has the existing name, color control, management menu and description editor, collapsible and expanded when the description isn't empty.

`TagPageQueries.page` stays only for MCP `get_tag_page`/`get_context`, unchanged.

## Risks / Trade-offs

- **[Big UI swap]** Three lists and the tree leaves go away at once. → Build the browser next to them first (task 2.x behind the new destinations), switch the sidebar in one step (3.1), and remove the old views last (3.4). Checks compare the old scenarios.
- **[Tag tree without leaves feels like a loss]** It was a decision made in this proposal. → The click-filters-view flow puts the items one click away in the main area. If it's missed, leaves can come back as an option without changing the query model.
- **[Counts per view cost a second query]** → Same observation pattern as the results, over indexed columns; measured in the performance test (5,000 items).
- **[Text search with FTS prefix semantics]** "rev" matches "review". That's the same as ⌘K today, so it's expected.

## Migration Plan

No data migration. Saved views start empty. Rollback = an older build, which ignores the saved-views key.

## Open Questions

- Whether finished tasks should appear in All items by default (preset: no, `status:` open/snoozed applies to tasks there too). Can be tuned in the presets without changing the specs.
