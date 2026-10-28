# Tasks

## 1. Editor

- [ ] 1.1 Reveal-able syntax (L1): styler marks syntax ranges per line for headings, emphasis, code spans, list markers, checkboxes, quotes, fences and links; `MarkdownAttributes.apply` hides them outside a given set of revealed lines; verify with tests that each construct is hidden off the revealed lines and visible on them, and that the stored text never changes
- [ ] 1.2 Decorations (L1): `GlyTextView` draws bullets, numbers, checkboxes, quote bars and code-block backgrounds for hidden markers; checkbox clicks toggle as before; verify manually headings, lists, checklists, quotes and code blocks render without syntax
- [ ] 1.3 Revealed lines follow the selection (L2) and clicks (L3): re-style only the lines leaving/entering the revealed set; plain click follows a link chip on unrevealed lines; marked text keeps its line revealed; verify with tests for the revealed-set computation and manually "Back on the line" and "Link chip"
- [ ] 1.4 Source mode (L4): Edit → "Show Markdown Source" (checkmark) per focused editor; verify manually "See the raw text"

## 2. App

- [ ] 2.1 One mode (L5): remove Read/Edit pickers, ⌘E and the editing state from pages, tasks, meeting pages and tag pages; `editRequest` focuses the editor with the caret at the end; the Trash keeps the read view; verify manually on each page type, quick capture ⌘Return ("Save and open"), and "Trash preview" (Read-only text)

## 3. End to end

- [ ] 3.1 Write `docs/manual-checks-live-preview.md` (neutral test data) and push it with `scripts/manual-checks.py push`; covers each markdown construct rendered and revealed, link and checkbox clicks, typing at the start and end of styled lines, undo, multi-line selection, source mode, and quick capture; done when `pull` reports every check passed

## Workflow follow-up

- `/opsx:verify live-preview` and archive, then `task-properties`.
