# Spec Delta

## Purpose

Gives all free text in WorkDash (page text, task notes, tag page descriptions) one comfortable markdown editor on the Mac, with light styling while typing and a rendered read view.

## ADDED Requirements

### Requirement: Markdown stays visible and is styled while typing
The editor SHALL keep the markdown syntax visible and style it lightly as the user types: headings larger and bold, `**bold**` bold, `*italic*` italic, list and checklist markers aligned, inline and fenced code in a monospaced font, and links as distinct, clickable chips showing the target's title. Styling SHALL never change the stored text.

#### Scenario: Heading while typing
- **WHEN** the user types `## Decisions` on a new line
- **THEN** the line is shown as a heading, and the stored text is exactly `## Decisions`

#### Scenario: Link chip
- **WHEN** the text contains a link to the page "Atlas architecture"
- **THEN** the editor shows a chip "Atlas architecture" that opens the page when clicked with ⌘ held, while the cursor can still be placed in it

### Requirement: Web links
Markdown links to web addresses (`[text](https://…)`, also `http`, `mailto` and `message`) and bare `http(s)://` URLs SHALL be shown as links. In the editor ⌘-click opens them, in the read view a plain click does, using the system's default app. Web links SHALL NOT create backlinks.

#### Scenario: Markdown web link
- **WHEN** the text contains `[Design doc](https://example.com/doc)`
- **THEN** the editor shows "Design doc" as a link that opens the address in the browser with ⌘-click

#### Scenario: Bare URL
- **WHEN** the user pastes `https://example.com/report` into a page
- **THEN** it is shown as a link and opens with ⌘-click, and the stored text is unchanged

### Requirement: Checklists
Lines starting with `- [ ]` or `- [x]` SHALL be shown as checkboxes that can be toggled by clicking, which changes the text to `- [x]` or `- [ ]`.

#### Scenario: Tick a checklist item
- **WHEN** the user clicks the checkbox of `- [ ] send agenda`
- **THEN** the line becomes `- [x] send agenda` and is shown as done

### Requirement: Read view
The user SHALL be able to switch between editing and a rendered read view of the same text. In the read view, markdown is rendered (headings, emphasis, lists, checklists, code, quotes, links) without syntax characters, and a plain click on a link follows it. Pages SHALL open in the read view when they have text and in editing when they're empty.

#### Scenario: Toggle
- **WHEN** the user switches a page to the read view
- **THEN** headings, lists and links are rendered and links open with a single click

### Requirement: Same editor everywhere
The page text, task notes and tag page descriptions SHALL use the same editor and read view, including `[[` link insertion.

#### Scenario: Task notes
- **WHEN** the user opens a task in the task editor
- **THEN** its notes use the markdown editor with styling and `[[` links
