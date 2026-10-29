# Manual checks: bookmarks

Build and run: `scripts/build.sh`, quit gly, `open build/Build/Products/Debug/gly.app`.
Neutral test data only. Setup: Claude creates, under the tag `gly/checks/bookmarks/demo`: the bookmark "Latency dashboard" (`https://example.com/dashboards/latency`, description "p99 by service", tag `gly/checks/bookmarks/demo/ops`), the bookmark "Team wiki" (`https://example.org/wiki`, tag `gly/checks/bookmarks/demo`), the page "Demo: bookmarks" linking both plus the unbookmarked `[Runbook](https://example.net/runbook)`, and the task "Demo: bookmark from notes" with `[Release notes](https://example.net/release-notes)` in its notes.

## A. Links in text (task 2.1)

- [ ] A1 In "Demo: bookmarks", the "Latency dashboard" link shows a bookmark icon, "Runbook" a globe. Hovering the bookmarked link shows its title, "p99 by service", "#gly/checks/bookmarks/demo/ops" and the URL ("Hover a bookmarked link").
- [ ] A2 Click the globe before "Runbook" → a bookmark popover opens with title "Runbook" and its URL; Save → the icon turns into a bookmark. A plain click on the label still opens the browser.
- [ ] A3 Right-click a bookmarked link → "Edit Bookmark…" and "Copy Link" on top of the menu; Edit opens the popover with the stored description and tags; Copy Link puts the URL on the clipboard.
- [ ] A4 In the task "Demo: bookmark from notes", right-click "Release notes" → "Add to Bookmarks…" → title "Release notes" and the URL are filled in; Save creates the bookmark ("Bookmark a link from notes").
- [ ] A5 The same icon and tooltip in a meeting's notes and on a tag page's text (paste a bookmarked link there); in source mode (Edit → Show Markdown Source) the icon stays and the icon click still works.

## B. Bookmarks list (task 3.1)

- [ ] B1 The sidebar has "Bookmarks" with a count; the list shows each bookmark's title, host, tag chips and the first line of its description.
- [ ] B2 Click "Latency dashboard" → its page opens ("Open a bookmark"); ⌘-click → the URL opens in the default browser ("Open the URL").
- [ ] B3 Tag filter `gly/checks/bookmarks/demo` → both demo bookmarks (one carries a tag below it); `…/demo/ops` → only "Latency dashboard" ("Filter by tag"). The search field finds "p99" and "example.org".
- [ ] B4 "New Bookmark" with `https://example.com/dashboards/latency` → "Already bookmarked as “Latency dashboard”" with "Edit it", and Save is off; "Edit it" shows the existing bookmark ("Same URL again").
- [ ] B5 Create a bookmark with "New Bookmark", then ⌘Z (Edit menu says "Undo Add bookmark …") → it's gone ("Create a bookmark"); ⌘⇧Z brings it back.
- [ ] B6 Context menu: Open Page, Open URL, Copy URL, Delete → the bookmark is in the Trash (kind bookmark) and Restore brings it back with its tags.

## F. Bookmark page and tag tree (task 3.4)

- [ ] F1 The page of "Latency dashboard" shows the title, the URL with an Open button, the tag chip, the description "p99 by service" in the editor, and "Linked from" with "Demo: bookmarks".
- [ ] F2 Change the title, the URL and the tags on the page → each is saved at once and each is one ⌘Z step; an invalid URL (`ftp://x`) shows a red message and isn't saved; a URL another bookmark has is refused.
- [ ] F3 Write into the description, wait, write more → saved; ⌘Z (outside the text) takes the edit session back in one step ("Edit on the page"); `[[` links work in the description.
- [ ] F4 The sidebar tag tree lists both demo bookmarks under `gly/checks/bookmarks/demo` (and `…/demo/ops`) with a bookmark icon, after tasks and pages; a click opens the page; the counts didn't change; dragging a bookmark onto another tag retags it ("Tag tree").
- [ ] F5 Backlinks of "Demo: bookmarks"-like texts and search results open bookmark pages; deleting from the page goes back and puts it in the Trash.

## C. Tag pages, search, picker (task 3.2)

- [ ] C1 The tag page of `gly/checks/bookmarks/demo` has a "Bookmarks" section listing both demo bookmarks; a click opens the bookmark's page, ⌘-click the URL ("Tag page section").
- [ ] C2 ⌘K "p99" → "Latency dashboard" is among the results with the bookmark icon and "Bookmark · …" second line; Return opens the bookmark's page; ⌘Return the URL ("Search by description").
- [ ] C3 In a page, type `[[late` → the picker offers "Latency dashboard" with the bookmark icon; choosing it inserts `[Latency dashboard](https://example.com/dashboards/latency)` ("Insert from the picker").

## D. Quick capture (task 3.3)

- [ ] D1 In the capture panel, Tab cycles Task → Page → Bookmark → Task; the hint shows the next kind; Bookmark has a bookmark icon and its own placeholder.
- [ ] D2 Bookmark: paste `https://example.com #gly/checks/bookmarks/demo` → the preview shows "fetching title…", then "Example Domain · example.com · gly/checks/bookmarks/demo"; Return closes the panel, the previous app stays in front, and the bookmark "Example Domain" exists with that tag ("Capture a bookmark").
- [ ] D3 Bookmark with typed words: `https://example.com/typed Typed title` + ⌘Return → gly comes to the front on the page of "Typed title" with the cursor in the description.

## E. Agents (task 4.1, Claude's)

- [x] E1 (Claude) `create_bookmark` with a URL, title and the demo tag → the bookmark appears in the Bookmarks list and on the tag page; the same URL again returns it with `existing: true` ("Agent saves a link").
- [x] E2 (Claude) `list_bookmarks` with text "dashboard" → "Latency dashboard" with id, title, URL, description and tags ("Agent finds a link"); `delete_bookmark` + `restore` round-trip; the change log names the agent.
