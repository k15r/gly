# Manual checks: link-disambiguation

Build and run: `scripts/build.sh && open build/Build/Products/Debug/WorkDash.app`.
Neutral test data only (no real names). Setup: tags `person/alex` and `person/sam`; a page "Goals" tagged `person/alex` and a second page "Goals" tagged `person/sam`; a task "Review notes".

## A. Icons and qualifiers on links (task 3.1)

- [x] A1 In a new page, type `[[Review notes]]` → the chip shows a task icon (checkmark circle); a link to a page shows a page icon, a tag link a tag icon, `[text](https://example.com)` a globe. A bare URL shows just the address.
- [x] A2 Link one of the Goals pages (via the picker) → the chip reads "Goals · alex" (or the deepest tag that tells the two apart); the read view shows the same icon and qualifier.
- [x] A3 Retag the `person/alex` Goals page to `person/alex/work` → the qualifier updates without editing the linking page; the stored text is unchanged (open it via MCP `get_page` or check that ⌘Z doesn't change anything).
- [x] A4 Delete the second Goals page → the qualifier disappears (one Goals left).
- [x] A5 Caret, selection and scrolling around chips: arrow keys across a chip, select across it, type right after it, wrap a long line with chips, scroll up and down → no overlapping or misplaced icons or text. (If this misbehaves: fallback, icon only with the qualifier in the tooltip.)

## B. Picker, lists and search (task 3.2)

- [x] B1 Type `[[Goals` → the picker shows both pages with qualifiers and a second line "Page · person/… · edited …"; choosing one links exactly that page.
- [x] B2 ⌘K "Goals" → both entries with qualifier and second line.
- [x] B3 Pages list and the tag page of `person` show "Goals · alex" and "Goals · sam"; backlinks of a page linked from both Goals pages show both with qualifiers.

## C. Typed links and candidates (task 3.3)

- [x] C1 Type `[[person/alex/Goals]]` and leave the page → it becomes a link to the alex Goals page.
- [x] C2 Type `[[task:Review notes]]` → links the task; `[[page:Review notes]]` stays missing.
- [x] C3 Type `[[Goals]]` → it stays a missing link. ⌘-click it in the editor → a menu with both Goals pages, then "Create page …"; choose one → the link is set; one ⌘Z brings back `[[Goals]]`.
- [x] C4 Same in the read view: click the missing `[[Goals]]` → a dialog with both choices; choose one → the link is set; ⌘Z (in edit mode) undoes it.
- [x] C5 A missing link without candidates (`[[Nothing here]]`) still offers to create the page as before.

## D. Agents (task 4.1)

- [x] D1 Ask Claude Code: "Create a page 'Weekly' with the text 'see [[Goals]]'" → the answer mentions that `[[Goals]]` is ambiguous and lists both candidates; Claude retries with `[[person/alex/Goals]]` (or the id) and the link resolves.
- [x] D2 Ask Claude Code to create another page "Goals" → the response mentions `same_title`; ask it to read a page linking Goals → links carry `display` and `tags`.

## E. Added during testing

- [x] E1 Click a missing link in read mode → a native menu at the pointer (candidates, New page, New task); Esc closes it without changes.
- [x] E2 ⌘-click `[[person/alex/Call]]` in edit mode → "New task “Call” in person/alex" → the task opens, tagged `person/alex`; the link now points to it.
- [x] E3 Type `[[person/alex/` → the picker lists the pages and open tasks under `person/alex`, then its subtags; typing "go" narrows to titles starting with "go". `[[person/al` still offers the tag `person/alex` ("Link to a tag").
- [x] E7 Type `[[call` (no such item) → the picker offers "New page “call”" and "New task “call”"; New task inserts `[[task:call]]`, and clicking it offers only "New task".
- [x] E4 Right-click `person/alex` in the tree → New Subtag… "goals" → `person/alex/goals` appears below `alex` (count 0) and its tag page opens; the same from the tag page's "New Subtag" button; ⌘Z removes it.
- [x] E5 The tree shows the start of each item's text below its title; two same-titled pages under one tag can be told apart.
- [x] E6 Drag a task from the task list and a page from the pages list onto a tag in the tree → the tag is added, the other tags stay; ⌘Z undoes it.
