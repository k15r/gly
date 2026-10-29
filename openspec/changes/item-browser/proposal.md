# Proposal

## Why

Tasks, pages, bookmarks and meeting notes are all items with tags, dates, status and authors. But the sidebar offers three unrelated flat lists: Tasks (Open/Done/Dropped), Pages, Bookmarks. They have almost no filtering, and the tag tree only lists items under tags without letting you narrow anything down. Finding "what is relevant to me right now" means scrolling. The data to answer that question is already there; the views don't use it.

## What Changes

- **One item browser** replaces the task list, the pages list and the Bookmarks list. Sidebar entries (All items, Tasks, Pages, Bookmarks, Meetings) become preset views of it. **BREAKING** (UI): the Open/Done/Dropped switch and the separate lists go away; status and kind become filters.
- **A filter bar** with tokens:
  - kind, tags (including tags below; several = all; excluded tags)
  - task status, due date, priority, effort
  - last change, author (me or an agent), bookmark host
  - free text (the full-text search)

  Tokens can be typed (`is:task #project/atlas due:week`) or picked from a menu, and are shown as removable chips.
- **A "Refine" row** shows the tags that occur among the current results, with counts; one click narrows the results.
- **Grouping and sorting** per view: by kind, tag, due date or status; by relevance, last change, due date or title.
- **Saved views**: the current filter can be saved as a sidebar entry, renamed and deleted (per Mac).
- **Uniform rows**: every kind uses the same row layout, and task rows keep their status bar and quick actions. Everywhere, a click opens the item and ⌘-click opens its link (a bookmark's URL).
- **Tag tree** **BREAKING**:
  - It lists tags only (no items as leaves) and has a filter field.
  - Counts reflect the current view.
  - Clicking a tag filters the current view; ⇧-click adds the tag to the filter.
  - "Untagged" filters items without tags.
  - Items are dragged from the browser's rows onto tags.
- **Tag pages become the browser filtered by the tag**, grouped by kind, with the tag's name, color, management actions and description on top.
- ⌘K quick open stays; it gets "Show all results", which opens the browser with the typed text.

Decisions taken in this proposal (open for review):
- The tag tree shows tags only, because the browser shows the items.
- A tag click filters the current view instead of always switching to all items.

## Capabilities

### New Capabilities
- `item-browser`: the one list of items with preset and saved views, the filter bar and tokens, refine row, grouping and sorting, rows and how they open.

### Modified Capabilities
- `tasks`: "Task list" becomes the Tasks view of the browser (same default order; Done/Dropped through the status filter).
- `info-pages`: "Pages list" becomes the Pages view of the browser.
- `tags`: tag tree
  - "Filter tasks by tag including descendants" now applies to all items.
  - "Tag list" becomes tags only, with a filter field, view-relative counts and click-to-filter.
  - "Move items in the tree" now drags from the browser rows.
  - "Drop targets in the tree" now covers the tag rows only.
- `tag-pages`: "Tag page content" and "Open the tag page" become the tag view of the browser.
- `search`: "Quick open" offers "Show all results" in the browser.
- `bookmarks` (from the `bookmarks` change, which must be archived first):
  - "Bookmarks list" becomes the Bookmarks view.
  - "Bookmarks in the tag tree" is removed, since there are no item leaves any more.

## Impact

- **GlyCore:** a new query layer (`ItemQuery`: token parsing, SQL over `live_items`, `item_tags` and `search_index`, facet counts), with tests. It replaces `TaskQueries.taskList`, `PageQueries.list` (tag filter) and `TagQueries.leavesByTag`/`untaggedItems` as UI sources. Tag tree counts need a version relative to a query.
- **App:**
  - New `ItemBrowserView`, `FilterBar`, `ItemRow` and saved-view storage.
  - `Navigation.Destination` gets `.items(view)`, which replaces `.tasks`, `.pages` and `.bookmarks`; `.tag` renders the browser.
  - Removed: `TaskListView`, `PagesListView`, `BookmarksListView` and the tree leaves (`TreeLeafRow`, `ItemMove` from leaves).
  - The sidebar is rebuilt.
- **Not affected:** the Day view, item pages (task, page, bookmark, meeting), quick capture, MCP. An MCP `list_items` tool with the same filters is a follow-up.
- **Ordering:** after `bookmarks` (archive it first); independent of `readability`, `week-view` and `meeting-actions`.
