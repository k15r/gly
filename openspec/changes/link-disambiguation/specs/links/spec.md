# Spec Delta

## MODIFIED Requirements

### Requirement: Insert a link
In any markdown text (page text, task notes, tag page description), typing `[[` SHALL open a picker that searches pages, tasks and tags by title or name as the user types. Each entry SHALL show its kind (icon), its title with the duplicate qualifier when needed, and a second line with its tags and last change. Choosing an entry SHALL insert a link to it. The picker SHALL also offer to link a page that doesn't exist yet under the typed title.

#### Scenario: Link to an existing page
- **WHEN** the user types `[[atl` in a task's notes and picks the page "Atlas architecture"
- **THEN** the notes contain a link to that page, shown as "Atlas architecture"

#### Scenario: Link to a tag
- **WHEN** the user types `[[person/al` and picks the tag `person/alex`
- **THEN** the text contains a link to the tag page of `person/alex`

#### Scenario: Pick between same-titled pages
- **WHEN** pages "Goals" exist under `person/alex` and `person/sam` and the user types `[[goals`
- **THEN** the picker shows "Goals · person/alex" and "Goals · person/sam" with a page icon each, and the chosen one is linked

### Requirement: Links typed as text
A `[[…]]` typed or pasted as text (also by agents) SHALL be resolved when the text is saved. The text MAY start with `page:`, `task:` or `tag:` to restrict the kind. It SHALL match an item or tag whose title or name equals it (case-insensitive); if none does and the text contains `/`, it SHALL also match a page or task whose title equals the part after the last `/` and that carries the tag before it (or a tag below it). Exactly one match SHALL become a link to it; otherwise the text SHALL stay a "missing page" link.

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

## ADDED Requirements

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
