# markdown-editing Specification

## Purpose

Gives all free text in gly (page text, task notes, tag page descriptions) one comfortable markdown editor on the Mac, with light styling while typing and a rendered read view.

## Requirements

### Requirement: Live preview
The editor SHALL render markdown in place: headings larger and bold without `#`, bold, italic and inline code without their markers, checklist items as checkboxes, lists with a bullet or number, quotes with a bar, fenced code as a monospaced block, and links as chips showing the target's title. Lines with the caret or selection SHALL show their raw syntax instead, and a code block with the caret inside SHALL show both fence lines. Rendering SHALL never change the stored text.

#### Scenario: Heading while typing
- **WHEN** the user types `## Decisions` on a new line and moves the caret to the next line
- **THEN** the line shows "Decisions" as a heading without `##`, and the stored text is exactly `## Decisions`

#### Scenario: Back on the line
- **WHEN** the user moves the caret back onto that heading
- **THEN** the line shows `## Decisions` again until the caret leaves it

#### Scenario: Inside a code block
- **WHEN** the caret is on a line inside a fenced code block
- **THEN** the opening and the closing ``` lines are shown, and they disappear again when the caret leaves the block

#### Scenario: Link chip
- **WHEN** the text contains a link to the page "Atlas architecture" and the caret is on another line
- **THEN** the editor shows a chip "Atlas architecture" that opens the page with a plain click

### Requirement: Web links
Markdown links to web addresses (`[text](https://…)`, also `http`, `mailto` and `message`) and bare `http(s)://` URLs SHALL be shown as links. In the editor ⌘-click opens them, in the read view a plain click does, using the system's default app. Web links SHALL NOT create backlinks.

#### Scenario: Markdown web link
- **WHEN** the text contains `[Design doc](https://example.com/doc)`
- **THEN** the editor shows "Design doc" as a link that opens the address in the browser with ⌘-click

#### Scenario: Bare URL
- **WHEN** the user pastes `https://example.com/report` into a page
- **THEN** it is shown as a link and opens with ⌘-click, and the stored text is unchanged

### Requirement: Checklists
Lines starting with `- [ ]` or `- [x]` SHALL be shown as checkboxes that can be toggled by clicking, in the editor and in the read view, which changes the text to `- [x]` or `- [ ]`. In the read view, each toggle SHALL be saved at once as one undo step.

#### Scenario: Tick a checklist item
- **WHEN** the user clicks the checkbox of `- [ ] send agenda`
- **THEN** the line becomes `- [x] send agenda` and is shown as done

#### Scenario: Tick in the read view
- **WHEN** the user clicks the checkbox of `- [ ] send agenda` while reading a page
- **THEN** the text is saved with `- [x] send agenda`, the item is shown as done, and Undo unticks it

### Requirement: Same editor everywhere
The page text, task notes, meeting notes and tag page descriptions SHALL use the same live-preview editor, including `[[` link insertion and clickable checklists.

#### Scenario: Task notes
- **WHEN** the user opens a task
- **THEN** its notes are shown in the live-preview editor, rendered and editable in place

### Requirement: Read-only text
Places that only show text without editing it (such as the Trash preview) SHALL show it rendered: markdown without syntax characters, and a plain click on a link follows it. Editable text SHALL NOT have a separate read mode.

#### Scenario: Trash preview
- **WHEN** the user selects a deleted page in the Trash
- **THEN** its text is shown rendered, without syntax characters

### Requirement: Markdown source
The Edit menu SHALL offer "Show Markdown Source", which shows the whole text of the editor as raw markdown, with light styling only, until it is chosen again.

#### Scenario: See the raw text
- **WHEN** the user chooses Edit → Show Markdown Source on a page
- **THEN** every line shows its raw markdown; choosing it again returns to the live preview
