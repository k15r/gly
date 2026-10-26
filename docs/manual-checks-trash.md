# Manual checks: trash-bin

Build and run: `scripts/build.sh && open build/Build/Products/Debug/WorkDash.app`.
Neutral test data only (no real names). Setup: two pages "Goals" tagged `person/alex` and `person/bob`, a page "Hub" with a link to each (via the `[[` picker), and a task "Call the venue" tagged `project/atlas` with a due date.

## A. Trash view (task 3.2)

- [x] A1 Delete the task "Call the venue" in the app → the sidebar shows "Trash" with a count; the Trash lists the task with its tag, excerpt and "deleted just now by you".
- [x] A2 Ask Claude Code to delete the page "Goals" tagged `person/bob` → it appears at the top of the Trash, "by Claude Code".
- [x] A3 Select an entry → the preview shows title, tags and text read-only; links in it can be followed.
- [x] A4 Restore the task with the Restore button → it leaves the Trash and is open again with its due date and tag; the Edit menu shows "Undo Restore “Call the venue”"; ⌘Z puts it back in the Trash (overlay "Restore …").
- [x] A5 Restore via the row's context menu works the same.

## B. Broken links (task 3.1)

- [x] B1 On "Hub", the link to the deleted bob "Goals" is struck through; its tooltip mentions ⌘-click.
- [x] B2 ⌘-click it in edit mode → menu: "Restore “Goals”", a greyed "deleted … by Claude Code", "Link to “Goals · person/alex” instead", "Show in Trash"; Esc closes it without changes.
- [x] B3 Choose "Link to … instead" → this link now points to the alex page; the bob page stays in the Trash; one ⌘Z brings the old link back.
- [x] B4 In read mode, click the broken link → the same menu at the pointer; "Restore “Goals”" → the page is back and every link to it works again.
- [x] B5 "Show in Trash" → the Trash opens with that page selected.
- [x] B6 Missing links (`[[Nothing here]]`) still show their old menu (New page / New task).

## C. Agents and history (task 4.1)

- [x] C1 Ask Claude Code to delete a page and then "undo that" → it uses `list_trash` and `restore`; the page is back with its tags.
- [x] C2 Items deleted before this change (if any) show up in the Trash with who deleted them.
