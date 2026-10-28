# Design

## Context

- **Editor** (`GlyEditor`): `MarkdownStyler.runs(for:appearance:)` scans the text line by line (fences, headings, lists, checkboxes, quotes, emphasis, code spans, links) and returns `StyleRun`s. `MarkdownAttributes.apply` turns them into attributes. `.syntax` runs are dimmed. `.hidden` runs (link syntax) get a 0.01 pt clear font plus `wdHidden`, and the caret skips them. `GlyTextView` draws link decorations into kerning-reserved space and toggles checkboxes on click.
- **Read view** (`GlyMarkdownReadView`, SwiftUI) renders blocks for reading. It's used next to the editor behind a Read/Edit picker on pages, tasks, meeting pages and tag pages, and on its own in the Trash preview.
- **Opening for editing:** quick capture's ⌘Return sets `Navigation.editRequest`, which switches a page into edit mode and places the caret.

## Goals / Non-Goals

**Goals:**
- One mode for editable text: rendered, editable in place, raw syntax only where the caret is.
- Reuse the existing hidden-range mechanism rather than a second renderer.

**Non-Goals:**
- Tables, images or HTML.
- WYSIWYG toolbars. Formatting stays markdown typed by hand.
- Changing the read view used in read-only places.

## Decisions

### L1: Syntax runs become "reveal-able"

The styler marks every syntax character range with the line it belongs to:
- heading `#`s and the following space
- `**`, `__`, `*`, `_` and `` ` `` markers
- list markers `-`, `*`, `+` and `1.` with their space
- the checkbox `- [ ] ` / `- [x] `
- quote `> `
- fence lines
- link syntax (already hidden today)

`MarkdownAttributes.apply` takes a set of revealed line ranges:
- **On those lines** the syntax gets today's dimmed `.syntax` style.
- **Elsewhere** it gets the `.hidden` treatment.
- **A marker hidden on a line with a visual stand-in** gets kerning-reserved space and a decoration that `GlyTextView.draw` paints: a bullet, a number (shown as text from the marker), a checkbox (filled when checked), a quote bar along the line, or a code block background.

- **Alternative: attachments (`NSTextAttachment`) replacing the markers.** Rejected: attachments change the attributed string's length mapping and complicate selection and undo. Hidden ranges keep the text 1:1 with the stored markdown.

### L2: Revealed lines follow the selection

Fenced code blocks count as a whole: with the caret on any line of a block, both fence lines are shown, so the block's boundaries are visible while editing it (found while checking).

The text view tracks the revealed set: the paragraph ranges touched by the current selection(s), and only while the editor has focus. On `textViewDidChangeSelection` and on focus changes, the text is re-styled only if the set changed, so moving within a line costs nothing. The re-style covers the whole text, with the same pass typing already uses; per-line re-styling stays an option if long notes ever make it noticeable. While typing, the edited line is revealed anyway, so nothing jumps under the cursor. Multi-line selections reveal all their lines.

### L3: Clicks

- **Checkbox:** a click on a checkbox decoration toggles it, as today.
- **Link:** a plain click on a link chip on an unrevealed line follows the link. On a revealed line a click places the caret (⌘-click still follows).
- **Elsewhere:** clicks place the caret normally, which reveals that line.

### L4: Source mode

`GlyTextView` has a `showsSource` flag. When it's set, every line counts as revealed, giving today's visible-syntax styling. The Edit menu item "Show Markdown Source" is a checkmark item. It's sent through the responder chain to the focused editor, so it applies per editor and isn't persisted.

### L5: One mode in the app

- **Removed:** the Read/Edit pickers, ⌘E and the `editing` state in `PageView`, `TaskPageView`, `MeetingPageView` and the tag page. The editor is always shown, with backlinks below it.
- **Quick capture:** `Navigation.editRequest` becomes a "focus text" request; the page focuses the editor and puts the caret at the end.
- **Read-only places:** the Trash preview keeps `GlyMarkdownReadView`.

## Risks / Trade-offs

- **[Re-styling cost on caret moves]** → A re-style only happens when the caret changes lines; it's the same pass every keystroke already runs.
- **[Hidden ranges and IME/marked text]** → Lines with marked text are always revealed, so composition never touches hidden runs.
- **[Click to follow vs. click to edit]** A plain click on a chip now navigates. → It only does so on unrevealed lines; a click elsewhere on the line, or the arrow keys, reach the chip's text for editing, and ⌘-click keeps working.
- **[Accessibility]** Hidden syntax is still in the text, so VoiceOver reads raw markers. → Acceptable for now; noted for later.
