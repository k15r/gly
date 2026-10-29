# Tasks

## 1. Core

- [x] 1.1 Migration v9 (B1): rebuild `items` with `bookmark` in the kind check and a `url` column, the unique live-URL index, views and indexes recreated; verify with a migration test on a populated database (counts, tags, work, links, search index, foreign key check)
- [x] 1.2 Bookmark commands and queries (B2): create (existing URL returns it), update, delete/restore, list by tag and text, lookup by URL(s), URL normalization, search text, undo labels; verify with tests for "Create a bookmark", "Same URL again", "Filter by tag", "Search by description", restore from the Trash

## 2. Editor

- [ ] 2.1 Bookmarked web links (B3): bookmark icon and tooltip for bookmarked URLs, icon click and context menu with add/edit; verify with styler tests for the icon choice and manually "Hover a bookmarked link", "Bookmark a link from notes"

## 3. App

- [ ] 3.1 Bookmark editor popover (B4) and the Bookmarks list in the sidebar (B5); verify manually "Open a bookmark", "Filter by tag", "Same URL again"
- [ ] 3.2 Tag page section, search results and the `[[` picker (B5); verify manually "Tag page section", "Search by description", "Insert from the picker"
- [ ] 3.3 Quick capture Bookmark kind with title fetching and the network entitlement (B6); verify with a parser test for URL/title/tags and manually "Capture a bookmark"

## 4. Agents

- [x] 4.1 MCP tools (B7); verify with MCP tests for "Agent saves a link" (incl. existing URL), "Agent finds a link", update, delete and attribution

## 5. End to end

- [ ] 5.1 Write `docs/manual-checks-bookmarks.md` (neutral test data, example.com URLs) and push it; done when `pull` reports every check passed

## Workflow follow-up

- Independent of the other open changes except `status-colors` (row style); then verify and archive.
