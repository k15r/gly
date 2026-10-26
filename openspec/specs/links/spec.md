# links Specification

## Purpose

Connects pages, tasks and tags concretely through `[[…]]` links in markdown text, with backlinks on every target, so related information can be followed in both directions.

## Requirements

### Requirement: Insert a link
In any markdown text, typing `[[` SHALL open a picker that searches pages, tasks and tags by title or name as the user types, with prefixes and tag paths as in typed links. Each entry SHALL show its kind (icon), its title with the duplicate qualifier when needed, and its tags and last change. Choosing an entry SHALL insert a link to it. The picker SHALL also offer a page or a task that doesn't exist yet (a task as `[[task:…]]`).

#### Scenario: Link to an existing page
- **WHEN** the user types `[[atl` in a task's notes and picks the page "Atlas architecture"
- **THEN** the notes contain a link to that page, shown as "Atlas architecture"

#### Scenario: Link to a tag
- **WHEN** the user types `[[person/al` and picks the tag `person/alex`
- **THEN** the text contains a link to the tag page of `person/alex`

#### Scenario: Pick between same-titled pages
- **WHEN** pages "Goals" exist under `person/alex` and `person/sam` and the user types `[[goals`
- **THEN** the picker shows "Goals · person/alex" and "Goals · person/sam" with a page icon each, and the chosen one is linked

#### Scenario: Browse a tag path
- **WHEN** the user types `[[person/alex/`
- **THEN** the picker lists the pages and open tasks tagged `person/alex` or a tag below it, then the tags below it; typing on narrows the list by title

### Requirement: Links point to their target, not to a title
A link SHALL keep pointing to the same page, task or tag when the target is renamed. The displayed link text SHALL show the target's current title.

#### Scenario: Target renamed
- **WHEN** a task links to the page "Atlas architecture" and the page is renamed to "Atlas system design"
- **THEN** the link still opens that page and shows "Atlas system design"

### Requirement: Links typed as text
A `[[…]]` typed or pasted as text (also by agents) SHALL be resolved when the text is saved; a `page:`, `task:` or `tag:` prefix restricts the kind. It SHALL match an item or tag whose title or name equals it (case-insensitive); if none does and it contains `/`, a page or task titled like the part after the last `/` that carries the tag before it (or one below). Exactly one match SHALL become a link; otherwise it SHALL stay a "missing page" link.

#### Scenario: Unique title
- **WHEN** an agent writes "see [[Atlas architecture]]" and exactly one page has that title
- **THEN** the text links to that page

#### Scenario: Ambiguous or unknown title
- **WHEN** the text contains `[[Retro notes]]` and no item or tag has that title
- **THEN** it is shown as a missing-page link

#### Scenario: Tag path
- **WHEN** pages "Goals" exist under `person/alex` and `person/sam` and the text contains `[[person/alex/Goals]]`
- **THEN** it links to the "Goals" page tagged `person/alex`

#### Scenario: Kind prefix
- **WHEN** a page and a task are both titled "Offsite" and the text contains `[[task:Offsite]]`
- **THEN** it links to the task

#### Scenario: Resolved once
- **WHEN** a link was written as `[[person/alex/Goals]]` and the page later loses the tag `person/alex`
- **THEN** the link still points to the same page

### Requirement: Missing pages
A missing-page link SHALL be visibly different from a working link. Clicking it (⌘-click while editing) SHALL open a menu offering the candidates of an ambiguous link, then a new page and a new task. For a typed tag path (`person/alex/Goals`) the new item SHALL be titled after the last `/` and carry the tag before it. The new item SHALL be opened, and every link waiting for it SHALL then point to it.

#### Scenario: Create from a missing link
- **WHEN** the user clicks the missing-page link "Retro notes" and chooses "New page"
- **THEN** a page "Retro notes" is created and opened, and the link now points to it

#### Scenario: Create a task under a tag path
- **WHEN** the user clicks the missing link `[[person/alex/Call]]` and chooses "New task “Call” in person/alex"
- **THEN** a task "Call" tagged `person/alex` is created and opened, and the link now points to it

#### Scenario: Dismiss the menu
- **WHEN** the menu of a missing link is open and the user presses Esc or clicks elsewhere
- **THEN** the menu closes and nothing is created or changed

### Requirement: Deleted link targets
A link whose target was deleted SHALL stay in the text and be shown as "link target deleted". Clicking it (⌘-click while editing) SHALL open a menu offering to restore the target (with when and by whom it was deleted), to link to a live item of the same kind and title instead, and to show the target in the Trash. If the target is restored, the link SHALL work again.

#### Scenario: Linked task deleted
- **WHEN** a page links to a task and the task is deleted
- **THEN** the page shows the link as "link target deleted"

#### Scenario: Restore from a broken link
- **WHEN** the user clicks a link to the deleted page "Goals" and chooses "Restore “Goals”"
- **THEN** the page is restored, and this link and every other link to it work again

#### Scenario: Link to the surviving duplicate
- **WHEN** of two pages "Goals" the one tagged `person/bob` was deleted, and the user clicks a link to it and chooses "Link to “Goals · person/alex” instead"
- **THEN** this link points to the page tagged `person/alex`, the deleted page stays in the Trash, and one Undo brings the old link back

### Requirement: Backlinks
Every page, task and tag page SHALL show its backlinks: the pages, tasks and tag pages whose text links to it, with title and a short excerpt around the link. Items that were deleted SHALL NOT appear as backlinks.

#### Scenario: Backlinks on a page
- **WHEN** two tasks and one page link to the page "Atlas architecture"
- **THEN** that page lists the three of them under backlinks, each with an excerpt

#### Scenario: Backlinks update immediately
- **WHEN** the user removes a link from a task's notes
- **THEN** the task disappears from the target's backlinks without refresh

### Requirement: Follow links and navigate back
Clicking a link SHALL open its target in the main area: a page, a task (on its task page) or a tag page. The system SHALL let the user go back and forward through the opened pages, tasks and tag pages with ⌘[ and ⌘].

#### Scenario: Follow and go back
- **WHEN** the user clicks a link from page A to page B and then presses ⌘[
- **THEN** page B opens, and then page A is shown again

### Requirement: Kind shown on links
Links SHALL show the kind of their target with an icon (page, task, tag page, web link written as `[text](url)`) in the editor and the read view; bare URLs show the address itself, and missing-page links SHALL keep their distinct style.

#### Scenario: Task link
- **WHEN** a page links to a task
- **THEN** the link shows a task icon before the task's title

### Requirement: Duplicate titles are distinguishable
Wherever an item is shown by title (links, the link picker, quick open, search results, backlinks, tag page lists), a title that is not unique among live items of its kind SHALL be shown with a qualifier: the most specific tag of the item that none of the other same-titled items carries, or, if there is none, its creation date. The qualifier SHALL be derived from the current tags whenever it is shown, and SHALL NOT be stored in texts.

#### Scenario: Qualifier appears with a duplicate
- **WHEN** a page "Goals" tagged `person/alex` is linked and a second page "Goals" tagged `person/sam` is created
- **THEN** the existing link is shown as "Goals · person/alex" without its text changing

#### Scenario: Qualifier follows tag changes
- **WHEN** the page "Goals" tagged `person/sam` is retagged `person/kim`
- **THEN** links to it show "Goals · person/kim"

#### Scenario: Same tags
- **WHEN** two pages "Notes" carry exactly the same tags
- **THEN** each is shown with its creation date ("Notes · created 12 Oct")

### Requirement: Choose a target for an ambiguous link
For a typed link that matches several items, the editor and the read view SHALL offer the candidates (with kind and qualifier); choosing one SHALL replace the typed link with a link to it.

#### Scenario: Pick a candidate
- **WHEN** the text contains `[[Goals]]`, two pages match, and the user picks "Goals · person/alex" from the link's menu
- **THEN** the text links to that page
