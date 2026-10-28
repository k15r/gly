# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: Markdown stays visible and is styled while typing`
- TO: `### Requirement: Live preview`

## MODIFIED Requirements

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

### Requirement: Same editor everywhere
The page text, task notes, meeting notes and tag page descriptions SHALL use the same live-preview editor, including `[[` link insertion and clickable checklists.

#### Scenario: Task notes
- **WHEN** the user opens a task
- **THEN** its notes are shown in the live-preview editor, rendered and editable in place

## REMOVED Requirements

### Requirement: Read view
**Reason**: Editable text no longer has a separate read mode to switch to; the live preview renders it in place.
**Migration**: Pages, tasks, meeting pages and tag pages always show the live-preview editor; read-only places use "Read-only text".

## ADDED Requirements

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
