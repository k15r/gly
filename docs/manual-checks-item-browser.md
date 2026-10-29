# Manual checks: item-browser

Build and run: `scripts/build.sh`, quit gly, `open build/Build/Products/Debug/gly.app`.
Neutral test data only. Setup: Claude creates, under the tag `gly/checks/item-browser/demo` (short: `demo`):
- the tasks "Demo: overdue report" (due yesterday, high, effort M, `demo/atlas` + `demo/people/alex`), "Demo: review deck" (due in 2 days, `demo/atlas` + `demo/people/alex`), "Demo: plan offsite" (due in 3 days, `demo/atlas` + `demo/people/sam`), "Demo: later idea" (due in 20 days, `demo/atlas`), "Demo: no date" (`demo/ops`), "Demo: finished" (done, `demo/atlas`), "Demo: snoozed" (snoozed for a week, `demo/atlas`)
- the pages "Demo: atlas notes" (`demo/atlas`, text "notes about the review") and "Demo: ops runbook" (`demo/ops`)
- the bookmarks "Demo: dashboard" (`https://example.com/dashboard`, `demo/atlas`) and "Demo: wiki" (`https://example.org/wiki`, `demo/ops`)
- the untagged page "Demo: untagged page"

All are created by an agent (Claude), so `by:agent` finds them.

## A. Views and sidebar (tasks 2.1, 3.1)

- [ ] A1 The sidebar shows Day, All items, Tasks, Pages, Bookmarks, Meetings and Trash (counts on all but Day and All items); Tasks lists open and snoozed tasks, urgent first, then by due date; the snoozed demo task is listed, marked with its snooze date ("Tasks view", "Default sorting", "Snoozed tasks stay visible").
- [ ] A2 In Tasks add `#gly/checks/item-browser/demo/atlas`, open a task, go back → still filtered; "Reset" brings back the preset ("Back to a view").
- [ ] A3 In Tasks remove the status chips and add `status:done` → "Demo: finished" (and other done tasks), most recently completed first ("Show completed tasks").
- [ ] A4 Pages lists pages, most recently changed first; editing an older page moves it to the top ("Recently changed first"); filtering by `#gly/checks/item-browser/demo` shows only the demo pages ("Filter by tag").
- [ ] A5 In Tasks filter by the demo tag and `due:week`, click "Save View…" (highlighted once the filter is changed) or press ⌘S, name it "Demo this week" (the field suggests a name from the filter) → it appears under Saved Views and opens with that filter; quit and reopen gly → still there ("Save a view"); right-click → Rename…, Delete View work; a changed saved view offers "Update View".
- [ ] A6 ⌘1–⌘4 and ⌘0 open Day, Tasks, Pages, Bookmarks and All items; ⌘N in Tasks opens the new-task form, in Pages the new-page sheet.

## B. Filter bar (task 2.2)

- [ ] B1 In All items type `is:task #gly/checks/item-browser/demo/atlas due:week review` → only "Demo: review deck" (and "Demo: atlas notes" is not listed, it's a page); the bar shows three chips plus the word ("Typed tokens").
- [ ] B2 In Bookmarks add `-#gly/checks/item-browser/demo/ops` → "Demo: wiki" disappears ("Exclude a tag").
- [ ] B3 `by:agent changed:today` in All items lists the demo items ("Agent changes"); `by:me` doesn't.
- [ ] B4 Typing `#gly/ch` suggests matching tags, `is:` suggests task/page/bookmark/meeting, `due:` its values; clicking a suggestion makes it a chip. The ⊕ menu adds every kind of filter; ✕ on a chip and Backspace in the empty field remove chips.
- [ ] B5 Plain words search titles and texts: `offsite` finds "Demo: plan offsite"; `review` also finds "Demo: atlas notes" by its text.

## C. Results (task 2.3)

- [ ] C1 In All items click "Demo: dashboard" → its page; back, ⌘-click it → https://example.com/dashboard opens in the browser ("Open a bookmark from the browser"). ⌘-click on a page or task opens its page.
- [ ] C2 Task rows in the browser have the status bar (red for the overdue one) and, on hover, snooze, due date, priority, effort and open buttons; right-click shows the task actions ("Task row keeps its actions").
- [ ] C4 Group ▸ Due date in Tasks (demo-filtered) → "Overdue", "This week", "Later", "No due date" in that order; Group ▸ Tag and Status group accordingly; Sort menus reorder; clicking a group heading (chevron) collapses and expands it ("Group by due date").
- [ ] C5 In Tasks filtered by `#gly/checks/item-browser/demo/atlas` choose New Task → the form already has that tag; New in All items offers task, page and bookmark, each with the view's tags ("New task in a tag view").
- [ ] C7 Give a demo task eight tags (or narrow the window): its row shows the tags that fit and "+N"; hovering "+N" opens a small popup with the others (a click keeps it open; its chips open tag pages); nothing is cut off or overlaps ("Many tags").
- [ ] C6 Right-click a page or bookmark row → Open, (Open URL, Copy URL), Delete; Delete moves it to the Trash.

## D. Tag tree (task 3.2)

- [ ] D1 The tag tree shows tags only (no items below them); in Tasks `demo/atlas` counts its open tasks, in Bookmarks it counts 1 ("Tag hierarchy with counts", "Counts follow the view"); an unused tag shows no number ("Empty tag").
- [ ] D2 In Pages click `…/demo` → only demo pages, and the tag expands ("Click filters the view"). In Bookmarks click `demo/atlas`, ⌘-click `demo/ops` → both in the filter (nothing left); ⌘-click `demo/atlas` again → only `demo/ops` bookmarks ("⌘-click adds and removes"). ⌥-click a tag → its tag page ("⌥-click opens the tag page"); Control-click → its menu; in the Day view a plain click opens the tag page.
- [ ] D3 Type `peop` into "Filter tags" → only `…/demo/people` with `alex` and `sam` (and their parents) remain, expanded ("Find a tag").
- [ ] D4 In Pages click "Untagged" → "Demo: untagged page" (among other untagged pages) ("Untagged").
- [ ] D5 In Pages filtered by `#gly/checks/item-browser/demo/ops`, drag "Demo: ops runbook" onto `demo/atlas` → moved (only `demo/atlas` now); drag it back with ⌥ → both tags ("Move a page", "Alias a page"); from an unfiltered view a drop adds the tag ("Tag from a list"); a task moves the same way ("Move a task").
- [ ] D6 While dragging, a collapsed tag expands after resting on it; dropping onto a tag's name works ("Collapsed tag opens while dragging", "Drop onto the tag text"); right-click a tag → "Open Tag Page", color, rename, delete still work.

## E. Tag views (task 3.3)

- [ ] E1 Open the tag page of `…/demo/atlas` (chip click or "Open Tag Page") → name, color, description (collapsible), then the items grouped as Open tasks, Pages, Bookmarks, Finished tasks (collapsed) ("Project tag page", "From a chip").
- [ ] E2 The tag page of `…/demo/people` shows the tasks of `alex` and `sam` ("Group tag"); a meeting tagged below a tag shows under Meetings ("Person's meetings").
- [ ] E3 On the `…/demo/atlas` tag page add `due:week` → only the tasks due this week, still grouped, description above ("Narrow a tag page"); the kind switch (All/Tasks/Pages/Bookmarks/Meetings) narrows to one kind.
- [ ] E4 ⌘K, type `demo`, choose "Show all results" → All items opens filtered by the text, where chips can be added ("Show all results"); Return on a bookmark result opens its page, ⌘Return its URL.

## G. Views in the store, agents (tasks 5.2, 5.3)

- [ ] G1 Views you saved before this build appear under Saved Views again (imported once, not twice after a restart); saving, renaming, deleting and "Update View" still work, and ⌘Z undoes a save, rename or delete you made ("Save a view").
- [ ] G2 Under Saved Views there is "Demo: atlas this week", created by Claude over MCP; it shows "Demo: review deck" and "Demo: plan offsite", grouped by due date ("Agent saves a view").
- [x] G3 (Claude) MCP: `list_views`, `create_view`, `update_view`, `delete_view`, `list_items` by view and by filter work end to end, presets are read-only ("Agent changes and deletes a view", "Preset views are read-only", "Agent runs a view", "Agent filters directly").

## H. Refinements

- [ ] H1 In Tasks add "Due ▸ Within 2 workdays" → tasks due from today through the second working day (weekends and non-working days of Settings ▸ Planning don't count); the chip reads "Due: within 2 workdays"; typing `due:5wd` works too ("Due within working days").
- [ ] H2 In Pages the ⊕ menu has no Status, Due, Priority or Effort, and Group/Sort offer no task groupings or task order; in Tasks and All items they are there. Host and Exclude Tag are no longer in the menu ("Filters that fit the kinds").
- [ ] H3 ⊕ ▸ Tag is a nested menu following the tag hierarchy; a group offers "Filter by “…”" first.
- [ ] H4 Group offers Priority, Effort and Last change; grouping Tasks by priority puts urgent first.
- [ ] H5 In Bookmarks the tag tree shows only tags that carry bookmarks (counts match the list); "Show all tags" brings back the others; in Pages the counts follow Pages ("Tree follows the view").
- [ ] H6 Change the filter of a saved view → "Update View" appears next to Reset and writes the change into the view.

## F. Claude's checks

- [ ] F1 (Claude) While you watch Tasks filtered by `#gly/checks/item-browser/demo/atlas`, Claude creates a task with that tag over MCP → it appears without any action ("Agent adds a task").
- [x] F2 (Claude) Browser query performance with 5,000 items: the unit test passes; in a release build all 5,000 load in ~40 ms ("Browser is fast").
