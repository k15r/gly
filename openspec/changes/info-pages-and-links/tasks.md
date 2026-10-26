# Tasks

## 1. Store: v2 migration and derived indexes

- [x] 1.1 Add the `v2` migration (design P2): `change_log.session`, `link_index`, `search_index` (FTS5, `unicode61 remove_diacritics 2`, `prefix='2 3 4'`), with backfill from existing tasks and tags; check how an older migrator treats a database with `v2` applied and record the rollback path in `design.md`; verify with schema tests that a v1 database migrates, backfills, and that the new tables aren't in `Schema.syncedTables`
- [x] 1.2 Implement the link parser (canonical `[label](workdash://item|tag/<uuid>)`, missing `[[Title]]`, ranges; ignores links inside code spans/fences and web links) and plain-text extraction for search; verify with unit tests for each form, nested brackets, code exclusion, web links not indexed, and ranges
- [x] 1.3 Implement `DerivedIndex.refresh` and hook it into `Batch.insert`/`update` for `title`, `body`, `name`, `page_body`, `deleted_at` of items and tags, plus `DerivedIndex.rebuild`; verify with tests that create, edit, delete, undo and redo of a task leave `link_index` and `search_index` matching a fresh rebuild

## 2. Core: pages, resolution, sessions

- [x] 2.1 Add `createPage`, `updatePage`, `deletePage`, `updateTagPage` commands with validation (non-empty title; tag page creates a missing tag row) and undo labels for pages and tag pages; verify with command tests for "Minimal page", "Empty title", "Undo a page deletion", "Describe a person" and the new labels
- [x] 2.2 Implement `LinkResolver` in every markdown-writing command (unique case-folded title/name → canonical; else stays `[[…]]`; returns unresolved titles), resolve all missing links with the same title on page creation in the same batch, and refresh labels on rename; verify with tests for "Unique title", "Ambiguous or unknown title", "Create from a missing link" (other texts rewritten, one undo reverts all) and "Target renamed"
- [x] 2.3 Implement session coalescing (same writer, item, session → append to the latest live batch; `TaskPatch`/`PagePatch`/`updateTagPage` carry `session`); verify with tests: three saves in one session undo in one step; a different session or another writer's batch is never merged
- [x] 2.4 Implement `PageQueries`, `LinkQueries` (outgoing with current titles and deleted/missing states, backlinks with excerpts from live sources), `TagPageQueries` (description + open tasks / pages / finished tasks, descendants included) and the tag tree including page-only tags; verify with tests for "Recently changed first", "Filter by tag", "Backlinks on a page", "Linked task deleted", "Project tag page", "Group tag", "Tag used only on pages"
- [x] 2.5 Implement `SearchQueries.search` (token quoting, last-token prefix, per-kind bm25, snippets, live rows only) and a 10k-item benchmark test; verify "Prefix match", "Diacritics", "Grouped results", deleted items not found, and median query time under 100 ms (target: under 10 ms)

## 3. MCP

- [x] 3.1 Add `create_page`, `get_page`, `update_page`, `delete_page`, `search`, `get_context`, `get_tag_page`, `update_tag_page` with schemas and link-writing guidance in descriptions; extend `get_task` with `links`/`backlinks`; responses carry canonical text and `unresolved`; verify with tool tests for "Meeting notes from an agent", "Partial page update", "Agent links by title", "Unresolved link reported", "Find notes", "Context of a page", "Describe a project", "Task with links", and the tool list scenario (15 tools)

## 4. App: editor

- [x] 4.1 Implement `MarkdownStyler` (headings, emphasis, inline/fenced code with cross-line state, lists with hanging indent, checklists, quotes, dimmed syntax, collapsed canonical link URLs drawn as chips with current titles, web links and bare URLs styled as links) as a pure function over an attributed string; verify with unit tests on attribute runs for each construct and that the string content never changes
- [x] 4.2 Implement `MarkdownEditor` (`NSTextView` wrapper): live restyling of edited paragraphs, caret skipping collapsed ranges, ⌘-click on chips and web links (opens the browser), checkbox toggling, debounced/focus-loss saving with a session id, no external overwrite while focused or dirty; verify manually: typing a heading, toggling a checklist item, ⌘-click on a chip, "Markdown web link", "Bare URL", and that one edit session is one ⌘Z step after leaving the field
- [x] 4.3 Implement the `[[` picker popover (live search across pages/tasks/tags + "Create page …") inserting canonical links; verify manually "Link to an existing page" and "Link to a tag"
- [x] 4.4 Implement `MarkdownReadView` (blocks + inline `AttributedString(markdown:)`, `workdash://` handling via `OpenURLAction`, missing-link styling, deleted-target styling, web links opening in the browser); verify manually "Toggle", following a link with one click, a web link opening in the browser, a missing link creating a page, and a deleted target shown as "link target deleted"

## 5. App: pages, tag pages, navigation, search

- [x] 5.1 Replace `Navigation` with a destination stack (day, tasks, pages, calendars, page, tag) with ⌘[ / ⌘] and sidebar integration; task links open the task editor sheet; verify manually "Follow and go back" and that sidebar selection still works
- [x] 5.2 Add the Pages list (most recent first, tag filter, New Page ⌘N / ⌘⇧N) and `PageView` (title, tags, editor/read toggle ⌘E, backlinks, delete); verify manually page create/edit/delete/undo and that an agent's edit appears unless the user is typing
- [x] 5.3 Add `TagPageView` (description editor, three groups, "Show in Tasks", backlinks) and route sidebar tags and tag chips to it; verify manually "Project tag page", "Group tag", "From a chip", "Select a tag"
- [x] 5.4 Extend the sidebar tag tree with item leaves (exact-tag open tasks, snoozed marked, then pages, after child tags; "also in …" hint; "Untagged" node) and drag & drop for tasks and pages (plain = move, ⌥ = alias, onto Untagged = remove tag; one update each); verify with a query test for "Items as leaves of the tree", "Item with two tags", "Untagged items", and manually "Move a page", "Alias a page" and "Move a task" including one ⌘Z each
- [ ] 5.5 Add quick open (⌘K: grouped live results, keyboard navigation, Return opens, "Create page …"); verify manually "Open a page" and "Create from quick open"
- [ ] 5.6 Switch the task editor's notes to `MarkdownEditor` with session saving; verify manually "Task notes" and "Notes link to a page"

## 6. End to end

- [ ] 6.1 Manual checks documented in `docs/manual-checks-pages.md`: build a small wiki (a project tag page, two linked pages, a task linking a page), rename a page and see links follow, delete and restore via undo, search and quick open, backlinks update live; an agent (Claude Code) creates a meeting-notes page with `[[…]]` links and reads `get_context`; everything uses neutral test data

## Workflow follow-up

- Run `/opsx:verify info-pages-and-links`, then archive after the manual checks pass.
- Full-featured markdown editor (later): list editing feels odd today (no list continuation on Return, no indent and outdent with Tab), noted in manual check A1.
- Feature request (later): convert a checklist item into a task. The line would become a link to the new task, and the task would link back to its page.
- Later changes: link types, properties/templates, appointment notes and links, trash bin, iPhone editor, Obsidian import.
