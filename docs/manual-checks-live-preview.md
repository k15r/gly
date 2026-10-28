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

- [x] A1 With the cursor elsewhere (or the editor not focused): "Agenda" is a heading without `##`; bold, italic and code show without `**`, `*` and backticks; the list shows a bullet, the quote a bar, the checklist boxes; the link is a chip ("Heading while typing").
- [x] A2 Put the cursor on the heading line → it shows `## Agenda`; move away → rendered again ("Back on the line").
- [x] A3 Click a checkbox (not on the cursor line) → it toggles; ⌘Z undoes it.
- [x] A4 A plain click on the link chip opens the page; on the cursor line, a click places the cursor instead (⌘-click still opens) ("Link chip").
- [x] A5 Type at the start and at the end of a bold word, a heading and a checklist item → the text stays correct and nothing jumps under the cursor.
- [x] A6 Select across several lines → all of them show their raw syntax.
- [x] A7 Fenced code (```) shows as a code block; with the cursor anywhere inside the block, both ``` lines show; outside, they're hidden ("Inside a code block").

## B. Source mode and one mode (tasks 1.4, 2.1)

- [x] B1 Edit → Show Markdown Source (checkmark) → every line shows its raw markdown; choose it again → back to the live preview ("See the raw text").
- [x] B2 Pages, tasks, meeting pages and tag pages have no Read/Edit switch; ⌘E does nothing there.
- [x] B3 Quick capture: type a page title, ⌘Return → the page opens with the cursor in its text ("Save and open").
- [x] B4 Delete the demo page and select it in the Trash → its text is shown rendered, read-only ("Trash preview").
