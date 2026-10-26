# Spec Delta

## Purpose

Connects pages, tasks and tags concretely through `[[…]]` links in markdown text, with backlinks on every target, so related information can be followed in both directions.

## ADDED Requirements

### Requirement: Insert a link
In any markdown text (page text, task notes, tag page description), typing `[[` SHALL open a picker that searches pages, tasks and tags by title or name as the user types. Choosing an entry SHALL insert a link to it. The picker SHALL also offer to link a page that doesn't exist yet under the typed title.

#### Scenario: Link to an existing page
- **WHEN** the user types `[[atl` in a task's notes and picks the page "Atlas architecture"
- **THEN** the notes contain a link to that page, shown as "Atlas architecture"

#### Scenario: Link to a tag
- **WHEN** the user types `[[person/al` and picks the tag `person/alex`
- **THEN** the text contains a link to the tag page of `person/alex`

### Requirement: Links point to their target, not to a title
A link SHALL keep pointing to the same page, task or tag when the target is renamed. The displayed link text SHALL show the target's current title.

#### Scenario: Target renamed
- **WHEN** a task links to the page "Atlas architecture" and the page is renamed to "Atlas system design"
- **THEN** the link still opens that page and shows "Atlas system design"

### Requirement: Links typed as text
A `[[Title]]` typed or pasted as text (also by agents) SHALL be resolved when the text is saved: if exactly one page, task or tag has that title or name (case-insensitive), it SHALL become a link to it. Otherwise it SHALL stay a "missing page" link.

#### Scenario: Unique title
- **WHEN** an agent writes "see [[Atlas architecture]]" and exactly one page has that title
- **THEN** the text links to that page

#### Scenario: Ambiguous or unknown title
- **WHEN** the text contains `[[Retro notes]]` and no item or tag has that title
- **THEN** it is shown as a missing-page link

### Requirement: Missing pages
A missing-page link SHALL be visibly different from a working link. Clicking it SHALL create a page with that title and open it, and the link SHALL then point to the new page.

#### Scenario: Create from a missing link
- **WHEN** the user clicks the missing-page link "Retro notes"
- **THEN** a page "Retro notes" is created and opened, and the link now points to it

### Requirement: Deleted link targets
A link whose target was deleted SHALL stay in the text and be shown as "link target deleted". If the target is restored, the link SHALL work again.

#### Scenario: Linked task deleted
- **WHEN** a page links to a task and the task is deleted
- **THEN** the page shows the link as "link target deleted"

### Requirement: Backlinks
Every page, task and tag page SHALL show its backlinks: the pages, tasks and tag pages whose text links to it, with title and a short excerpt around the link. Items that were deleted SHALL NOT appear as backlinks.

#### Scenario: Backlinks on a page
- **WHEN** two tasks and one page link to the page "Atlas architecture"
- **THEN** that page lists the three of them under backlinks, each with an excerpt

#### Scenario: Backlinks update immediately
- **WHEN** the user removes a link from a task's notes
- **THEN** the task disappears from the target's backlinks without refresh

### Requirement: Follow links and navigate back
Clicking a link SHALL open its target: a page or tag page in the main area, a task in the task editor. The system SHALL let the user go back and forward through the opened pages, tasks and tag pages with ⌘[ and ⌘].

#### Scenario: Follow and go back
- **WHEN** the user clicks a link from page A to page B and then presses ⌘[
- **THEN** page B opens, and then page A is shown again
