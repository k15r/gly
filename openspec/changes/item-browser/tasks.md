# Tasks

## 1. Core

- [x] 1.1 `ItemQuery` with token parsing and canonical text (I1); verify with parser tests for every token of the spec "Filter bar", unknown tokens as text, and parse/print round trips
- [x] 1.2 `BrowseQueries.items` (I1): SQL for kinds, tags with descendants, exclusions, untagged, status, due, priority, effort, changed, author, host and FTS text, plus the sort orders; verify with tests for "Typed tokens", "Exclude a tag", "Agent changes", "Filter by prefix", "No partial segment match", task-list order and done-tasks order, and a 5,000-item performance test (< 100 ms)
- [x] 1.3 Facets and view-relative tag counts (I2), grouping (I5); verify with tests for "Group by due date", "Tag hierarchy with counts", "Counts follow the view", "Empty tag"

## 2. Browser

- [ ] 2.1 `ItemView` presets and saved-view storage, `BrowserModel` with per-view state and Reset, `.items(view)` destination (I3); verify with a storage round-trip test and manually "Tasks view", "Back to a view"
- [ ] 2.2 Filter bar with chips, typed tokens, suggestions and the add-filter menu (I4); verify manually "Typed tokens", "Exclude a tag", "Agent changes"
- [ ] 2.3 Results: `ItemRow` (TaskRow for tasks), click / ⌘-click via `ItemOpen`, drag with the source tag, context menus, group and sort menus, New Task/Page/Bookmark with the view's tags (I5, I6); verify manually "Open a bookmark from the browser", "Task row keeps its actions", "Group by due date", "New task in a tag view", "Agent adds a task"

## 3. Sidebar, tag tree, tag views

- [ ] 3.1 Sidebar: preset views with counts, saved views with rename/delete and "Save View…", replacing Tasks/Pages/Bookmarks (I3); verify manually "Save a view", "Default sorting", "Snoozed tasks stay visible", "Show completed tasks", "Recently changed first"
- [ ] 3.2 Tag tree: tags only, filter field, view-relative counts, click filters and expands, ⌘-click adds/removes, ⌥-click opens the tag page, Untagged, "Open Tag Page", drops on tag rows with move/alias from the view's tag (I7); verify manually "Click filters the view", "Find a tag", "Untagged", "Move a page", "Alias a page", "Move a task", "Tag from a list", "Collapsed tag opens while dragging", "Drop onto the tag text"
- [ ] 3.3 Tag view: browser with `#tag`, grouped by kind, header with name, color, management and description; chips and tag links open it; ⌘K "Show all results" (I8); verify manually "Project tag page", "Group tag", "Person's meetings", "Narrow a tag page", "From a chip", "Show all results"
- [x] 3.4 Remove the replaced views and code (`TaskListView`, `PagesListView`, `BookmarksListView`, `TagPageView` body, tree leaves, `leavesByTag`/`untaggedItems` if unused, `BookmarkOpen.click`), keeping specs/tests green; verify with the full test suite, lint and a build

## 5. Views in the store, agents

- [x] 5.1 Migration v10 `views` table, view commands with undo labels, `ViewQueries` (I3); verify with tests for create/update/delete, undo, labels and the migration
- [ ] 5.2 App: saved views from the store (sidebar, Save View, Update View, rename, delete through commands), one-time import from `UserDefaults` (I3); verify manually "Save a view" again and that views saved before reappear once
- [x] 5.3 MCP tools `list_views`, `create_view`, `update_view`, `delete_view`, `list_items` (I9); verify with MCP tests for "Agent saves a view", "Agent changes and deletes a view", "Preset views are read-only", "Agent runs a view", "Agent filters directly"

## 4. End to end

- [ ] 4.1 Write `docs/manual-checks-item-browser.md` (neutral test data) and push it; done when `pull` reports every check passed

## Workflow follow-up

- Archive `bookmarks` before archiving this change; its delta modifies the `bookmarks` spec.
