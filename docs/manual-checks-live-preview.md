# Manual checks: live-preview

Build and run: `scripts/build.sh`, quit gly, `open build/Build/Products/Debug/gly.app`.
Neutral test data only. Setup: a new page "Demo: live preview" (tag `gly/checks/live-preview/demo`) with this text:

```
## Agenda
Intro with **bold**, *italic* and `code`, a [[Demo: live preview]] link and https://example.com.
- first point
1. numbered
> a quote
- [ ] open item (S)
- [x] done item
```

## A. Rendering (tasks 1.2, 1.3)

- [ ] A1 With the cursor elsewhere (or the editor not focused): "Agenda" is a heading without `##`; bold, italic and code show without `**`, `*` and backticks; the list shows a bullet, the quote a bar, the checklist boxes; the link is a chip ("Heading while typing").
- [ ] A2 Put the cursor on the heading line → it shows `## Agenda`; move away → rendered again ("Back on the line").
- [ ] A3 Click a checkbox (not on the cursor line) → it toggles; ⌘Z undoes it.
- [ ] A4 A plain click on the link chip opens the page; on the cursor line, a click places the cursor instead (⌘-click still opens) ("Link chip").
- [ ] A5 Type at the start and at the end of a bold word, a heading and a checklist item → the text stays correct and nothing jumps under the cursor.
- [ ] A6 Select across several lines → all of them show their raw syntax.
- [ ] A7 Fenced code (```) shows as a code block; the fence lines show only when the cursor is on them.

## B. Source mode and one mode (tasks 1.4, 2.1)

- [ ] B1 Edit → Show Markdown Source (checkmark) → every line shows its raw markdown; choose it again → back to the live preview ("See the raw text").
- [ ] B2 Pages, tasks, meeting pages and tag pages have no Read/Edit switch; ⌘E does nothing there.
- [ ] B3 Quick capture: type a page title, ⌘Return → the page opens with the cursor in its text ("Save and open").
- [ ] B4 Delete the demo page and select it in the Trash → its text is shown rendered, read-only ("Trash preview").
