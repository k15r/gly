# Proposal

## Why

Text has two modes: an editor that shows markdown syntax, and a read view that renders it, switched with Read/Edit or ⌘E. In practice the toggle gets in the way: to change one word I switch to Edit, and the text jumps from rendered to raw. The editor already hides link syntax behind chips; doing that for all of markdown, except on the line being edited, gives one mode that reads well and edits in place, like Obsidian's live preview.

## What Changes

- **Live preview:** the editor renders markdown in place: headings without `#`, bold, italic and code without their markers, checklist items as checkboxes, list items with bullets or numbers, quotes with a bar, links as chips. Only the line(s) with the caret or selection show their raw syntax.
- **One mode:** the Read/Edit switch and ⌘E disappear from pages, tasks, meeting pages and tag pages. A plain click on a link (outside the line being edited) follows it.
- **Raw markdown when needed:** "Show Markdown Source" in the Edit menu shows the whole text raw until switched off again.
- **Read-only places**, such as the Trash preview, keep the rendered read view.
- Quick capture's ⌘Return opens the new item with the cursor in its text, without an "edit mode".

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `markdown-editing`: live preview replaces visible syntax; the read view is only for read-only places; source mode in the Edit menu.
- `quick-capture`: "opened in edit mode" becomes "opened with the cursor in its text".

## Impact

- `GlyEditor`: `MarkdownStyler` reports syntax ranges per line; the attribute pass hides them except on the caret lines and draws bullets, checkboxes and quote bars; the text view re-styles the lines left and entered when the selection moves; clicking a link chip follows it.
- App: the Read/Edit pickers and ⌘E go from `PageViews`, `TaskPageView`, `MeetingPageView` and tag pages; an Edit-menu command toggles source mode; the editing state and `editRequest` become a "focus the text" request.
- The task page's own requirement (`tasks` "Task page", which mentions ⌘E) is rewritten by `task-properties`, which follows this change.
