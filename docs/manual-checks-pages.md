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

- [ ] B1 Sidebar → Pages: all pages, most recently changed first; editing an older page moves it to the top.
- [ ] B2 ⌘1/⌘2/⌘3 switch Day/Tasks/Pages; ⌘[ / ⌘] go back and forward through visited pages and tag pages.
- [ ] B3 Rename a page (title field, Return) → links to it elsewhere show the new title.
- [ ] B4 A page shows "Backlinks" with the pages/tasks that link to it and an excerpt; removing the link elsewhere removes the backlink at once.
- [ ] B5 Delete a page (… menu) → gone from Pages, search and tag pages; ⌘Z brings it back with text and tags.
- [ ] B6 Click a tag in the sidebar or a tag chip on a task row → its tag page: description (Edit to write one, with `[[` links), open tasks, pages, finished tasks (collapsed), backlinks. "Show in Tasks" filters the task list.
- [ ] B7 Tag page of a group like `person` lists the items of all `person/…` tags; writing a description there works.
- [ ] B8 Sidebar tags: expanding `project/atlas` lists its pages after child tags; a page with two tags appears under both with a link icon ("Also in …"); untagged pages appear under "Untagged".
- [ ] B9 Drag a page from one tag onto another → it moves (one ⌘Z undoes it). Drag with ⌥ held → it's in both. Drag onto "Untagged" → that tag is removed.
- [ ] B10 While an agent (Claude Code) edits a page you have open but aren't typing in, the page updates by itself.

## C. Search and task notes (tasks 5.5, 5.6)

- [ ] C1 ⌘K, type part of a page title → grouped results (pages, tasks, tags) as you type; ↑/↓ + Return opens; `uberblick` finds "Überblick".
- [ ] C2 ⌘K with a new title → "Create page …" creates and opens it.
- [ ] C3 Open a task (double-click) → notes use the markdown editor with `[[` links; Save; the linked page lists the task under backlinks.

## D. End to end with an agent (task 6.1)

- [ ] D1 Build a small wiki: tag page for `project/atlas` with a description, two linked pages, one task linking a page.
- [ ] D2 Ask Claude Code to write meeting notes as a page with `[[…]]` links to existing pages and tag `project/atlas`, then to call `get_context` for it → links resolved, page appears in the app at once, under `project/atlas` in the sidebar.

## Results

| Date | Checked by | Result | Notes |
|---|---|---|---|
| 2026-10-26 | owner | A ✅ | Editor: styling, checklists (added: toggling in the read view), `[[` picker, chips, web links, one undo step per session, read view, missing/deleted links. List editing feels odd; full markdown editor is a later change |
| | | | |
