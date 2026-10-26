# Manual checks: info-pages-and-links

Build and run: `scripts/build.sh && open build/Build/Products/Debug/WorkDash.app`.
Use neutral test data only (no real names).

## A. Editor (tasks 4.2–4.4)

- [x] A1 New page (⌘⇧N) "Editor test", switch to Edit (⌘E). Type `## Decisions` on a line → shown as a heading; `**bold**`, `*italic*`, `` `code` ``, a fenced code block, `- item`, `> quote` are styled; the markdown stays visible (dimmed).
- [x] A2 Type `- [ ] send agenda`, click the box → becomes `- [x]`, line struck through. Click again → back.
- [x] A3 Type `[[` and a few letters of an existing page → picker shows pages/tasks/tags; ↑/↓ and Return insert the link as a chip with the page title. Typing `[[person/` offers tags ("Link to a tag").
- [x] A4 ⌘-click the chip → the page opens. ⌘[ goes back.
- [x] A5 Paste `https://example.com/report` and type `[Design doc](https://example.com/doc)` → both look like links; ⌘-click opens the browser.
- [x] A6 Type several words, click elsewhere (or switch page), then ⌘Z → the whole edit session is undone in one step (overlay shows "Edit page … (text)").
- [x] A7 Switch to Read: headings, lists, checkboxes, code, quotes render without syntax; a single click on a page link opens it; a web link opens the browser.
- [x] A8 `[[Retro notes]]` (no such page) shows red/dotted; clicking it (Read) or ⌘-clicking (Edit) creates and opens "Retro notes"; the original link now works.
- [x] A9 Delete a linked task → the link shows struck through ("link target deleted"); ⌘Z restores it and the link works again.

## B. Pages, navigation, tags (tasks 5.1–5.4)

- [x] B1 Sidebar → Pages: all pages, most recently changed first; editing an older page moves it to the top.
- [x] B2 ⌘1/⌘2/⌘3 switch Day/Tasks/Pages; ⌘[ / ⌘] go back and forward through visited pages and tag pages.
- [x] B3 Rename a page (title field, Return) → links to it elsewhere show the new title.
- [x] B4 A page shows "Backlinks" with the pages/tasks that link to it and an excerpt; removing the link elsewhere removes the backlink at once.
- [x] B5 Delete a page (… menu) → gone from Pages, search and tag pages; ⌘Z brings it back with text and tags.
- [x] B6 Click a tag in the sidebar or a tag chip on a task row → its tag page: description (Edit to write one, with `[[` links), open tasks, pages, finished tasks (collapsed), backlinks. "Show in Tasks" filters the task list.
- [x] B7 Tag page of a group like `person` lists the items of all `person/…` tags; writing a description there works.
- [x] B8 Sidebar tags: expanding `project/atlas` lists its open tasks (snoozed marked) and then its pages, after child tags; an item with two tags appears under both with a link icon ("Also in …"); untagged open tasks and pages appear under "Untagged". Clicking a task opens the task editor.
- [x] B9 Drag a page or a task from one tag onto another → it moves (one ⌘Z undoes it). Drag with ⌥ held → it's in both. Drag onto "Untagged" → that tag is removed.
- [x] B10 While an agent (Claude Code) edits a page you have open but aren't typing in, the page updates by itself.

## C. Search and task notes (tasks 5.5, 5.6)

- [x] C1 ⌘K, type part of a page title → grouped results (pages, tasks, tags) as you type; ↑/↓ + Return opens; `uberblick` finds "Überblick".
- [x] C2 ⌘K with a new title → "Create page …" creates and opens it.
- [x] C3 Open a task (double-click) → notes use the markdown editor with `[[` links; Save; the linked page lists the task under backlinks.

## E. Task page (task 5.7)

- [x] E1 Click a task (task list, day view, tag tree, tag page) → it opens in the main area like a page: title, field row, notes (Read/Edit ⌘E), backlinks; ⌘[ goes back.
- [x] E2 Follow a link to a task from a page → task page opens; its backlinks list the page with an excerpt.
- [x] E3 Change the due date, then edit the notes, then leave → both saved without a button; ⌘Z twice reverts them one by one.
- [x] E4 Tick the done checkbox, change priority, snooze until a date, change tags → each is saved at once; ⌘N still opens the new-task form.

## D. End to end with an agent (task 6.1)

- [x] D1 Build a small wiki: tag page for `project/atlas` with a description, two linked pages, one task linking a page.
- [x] D2 Ask Claude Code to write meeting notes as a page with `[[…]]` links to existing pages and tag `project/atlas`, then to call `get_context` for it → links resolved, page appears in the app at once, under `project/atlas` in the sidebar.

## Results

| Date | Checked by | Result | Notes |
|---|---|---|---|
| 2026-10-26 | owner | A ✅ | Editor: styling, checklists (added: toggling in the read view), `[[` picker, chips, web links, one undo step per session, read view, missing/deleted links. List editing feels odd; full markdown editor is a later change |
| 2026-10-26 | owner | B ✅ | Pages, navigation, tag pages, tree, drag & drop, live agent edits; fixed: tag tree counted snoozed tasks differently from tag pages (B7); added: open tasks as tree leaves next to pages (B8) |
| 2026-10-26 | owner | C ✅ | Quick open (grouped results, keyboard, create page), markdown task notes with links and backlinks |
| 2026-10-26 | owner | E ✅ | Task page (added after D1: tasks had no backlinks; tasks now open like pages, changes save at once); fixed: unlabeled due toggles, squeezed field row |
| 2026-10-26 | owner | D ✅ | End to end: small wiki (tag page, linked pages, task linking a page), meeting notes by Claude Code with resolved links and get_context |
| | | | |
