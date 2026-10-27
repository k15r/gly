# tags Specification

## Purpose

Groups tasks loosely with free, hierarchical tag names (for example `person/alex`, `project/atlas`), so related tasks can be found and filtered together without folders or fixed categories.

## Requirements

### Requirement: Tag names
A tag name SHALL be a non-empty string of one or more segments separated by `/`, where no segment is empty. Tag names SHALL be compared case-insensitively and stored with the casing first entered. Leading and trailing whitespace and `/` SHALL be removed. Nothing about the segments is predefined.

#### Scenario: Hierarchical tag
- **WHEN** the user tags a task with `person/alex`
- **THEN** the tag `person/alex` exists and is assigned to the task

#### Scenario: Invalid tag
- **WHEN** the user enters `project//atlas`
- **THEN** the tag is rejected with a message that segments must not be empty

#### Scenario: Same tag, different casing
- **WHEN** `Person/Alex` already exists and the user enters `person/alex`
- **THEN** the existing tag `Person/Alex` is assigned, and no second tag is created

### Requirement: Assign and remove tags
The system SHALL let the user add any number of tags to a task and remove them. Adding a tag that doesn't exist yet SHALL create it.

#### Scenario: New tag while editing
- **WHEN** the user adds the tag `project/atlas` to a task and no such tag exists
- **THEN** the tag is created and assigned

#### Scenario: Remove a tag
- **WHEN** the user removes `person/alex` from a task
- **THEN** the task no longer has that tag, and the tag still exists for other tasks

### Requirement: Filter tasks by tag including descendants
The system SHALL let the user filter the task list by a tag. The filter SHALL include tasks tagged with that tag or any tag below it in the hierarchy.

#### Scenario: Filter by prefix
- **WHEN** the user filters by `project` and tasks are tagged `project/atlas` and `project/atlas/logs`
- **THEN** both tasks are shown

#### Scenario: No partial segment match
- **WHEN** the user filters by `person/al` and a task is tagged `person/alex`
- **THEN** the task is not shown, because `al` is not a full segment

### Requirement: Tag list
The system SHALL show all tags as a hierarchy, including tags with no open items, with the number of open tasks per tag (including descendants); selecting a tag SHALL open its tag page and expand it. Each tag node SHALL list the open tasks and pages tagged exactly with it as leaves, each with the start of its text and a context menu to open or delete it; open tasks and pages without tags SHALL be listed under "Untagged".

#### Scenario: Tag hierarchy with counts
- **WHEN** two open tasks are tagged `person/alex` and one `person/sam`
- **THEN** the tag list shows `person` (3) with `alex` (2) and `sam` (1) below it

#### Scenario: Tag used only on pages
- **WHEN** the tag `topic/security` is assigned only to a page
- **THEN** it appears in the tag list with an open-task count of 0

#### Scenario: Empty tag and finished tag
- **WHEN** the tag `person/alex/goals` has nothing assigned and the tag `person/old` is assigned only to a done task
- **THEN** `goals` appears below `alex` and `old` below `person`, both with a count of 0

#### Scenario: Items as leaves of the tree
- **WHEN** the user expands `project/atlas` in the tag list, and one open task, one snoozed task, one done task and two pages are tagged `project/atlas`
- **THEN** after its child tags, the two open tasks are listed (the snoozed one marked as snoozed), then the two pages; the done task is not listed; clicking a task opens it in the task editor and clicking a page opens the page

#### Scenario: Delete from the tree
- **WHEN** the user right-clicks a page listed under `project/atlas` and chooses Delete
- **THEN** the page moves to the Trash and leaves the tag list, and one Undo brings it back

#### Scenario: Excerpt tells same-titled items apart
- **WHEN** two pages "Goals" with different text are listed under the same tag
- **THEN** each shows the start of its text below the title

#### Scenario: Item with two tags
- **WHEN** a page is tagged `project/atlas` and `project/beta`
- **THEN** it is listed under both `atlas` and `beta`, each time marked as also living in the other tag, and not as its own leaf under `project`

#### Scenario: Untagged items
- **WHEN** a page and an open task have no tags
- **THEN** both are listed under "Untagged" at the end of the tag list

#### Scenario: Select a tag
- **WHEN** the user selects `project/atlas` in the tag list
- **THEN** the tag page of `project/atlas` opens and `atlas` expands in the tag list

### Requirement: Move items in the tree
The user SHALL be able to drag a task or page in the tag list onto another tag node. A plain drop SHALL replace the tag the item was dragged from with the target tag (move); a drop with ⌥ held SHALL add the target tag and keep the others (alias). A drop onto "Untagged" SHALL remove the tag the item was dragged from. Tasks and pages dragged from the task list or the pages list SHALL get the target tag added. Each drop SHALL be one undo step.

#### Scenario: Move a page
- **WHEN** the user drags a page from `project/atlas` onto `project/beta`
- **THEN** the page is tagged `project/beta` instead of `project/atlas` and appears only under `beta`

#### Scenario: Alias a page
- **WHEN** the user drags a page from `project/atlas` onto `project/beta` with ⌥ held
- **THEN** the page has both tags and appears under both nodes

#### Scenario: Move a task
- **WHEN** the user drags an open task from `person/alex` onto `person/sam`
- **THEN** the task is tagged `person/sam` instead of `person/alex`

#### Scenario: Tag from a list
- **WHEN** the user drags a task tagged `person/alex` from the task list onto `project/atlas`
- **THEN** the task is tagged `person/alex` and `project/atlas`

### Requirement: Drop targets in the tree
Every row of a tag group (the tag itself and the items listed under it) SHALL accept drops for that tag, over its whole width including the text. While dragging, the tag group under the pointer SHALL be highlighted, and a collapsed tag SHALL expand when the drag rests on it for a moment.

#### Scenario: Drop onto an item of a group
- **WHEN** the user drags a page over a task listed under `project/beta` and drops it there
- **THEN** `project/beta` and its items are highlighted while hovering, and the page moves to `project/beta`

#### Scenario: Collapsed tag opens while dragging
- **WHEN** the user drags a page and holds it over the collapsed tag `project` for about half a second
- **THEN** `project` expands, so the page can be dropped onto one of its child tags or items

#### Scenario: Drop onto the tag text
- **WHEN** the user drops an item onto the name of a tag in the tree
- **THEN** the drop is accepted for that tag

### Requirement: Tag picker
Tags SHALL be added to a task or page through an "Add tag" menu that mirrors the tag hierarchy with submenus (for example project ▸ atlas). A group node that is also a tag SHALL be selectable itself. Each group SHALL offer "New tag in <group>/…" with the group prefilled, and the top level SHALL offer "New tag…". Tags already on the item SHALL not be offered again. New tag names SHALL follow the tag name rules.

#### Scenario: Pick a nested tag
- **WHEN** tags `project/atlas` and `project/beta` exist and the user opens "Add tag" on a task and chooses project ▸ atlas
- **THEN** the task gets the tag `project/atlas`

#### Scenario: New tag in a group
- **WHEN** the user chooses project ▸ "New tag in project/…" and enters `gamma`
- **THEN** the task gets the new tag `project/gamma`

#### Scenario: Invalid new tag
- **WHEN** the user enters `a//b` as a new tag
- **THEN** the tag is not added and the field says that segments must not be empty

### Requirement: New subtag
The tag list (context menu of a tag) and the tag page SHALL offer to create a subtag: the user enters a name (`/` for deeper levels), the tag `<parent>/<name>` is created if it doesn't exist, and its tag page opens. An existing tag's description SHALL stay unchanged. Creating a tag SHALL be one undo step.

#### Scenario: Subtag from the tree
- **WHEN** the user chooses "New Subtag…" on `person/alex` and enters "goals"
- **THEN** the tag `person/alex/goals` exists, appears below `alex`, and its tag page is open

### Requirement: Tag colors
Every tag SHALL have an effective color: its own color if set, else the nearest color set on a tag above it, else a color derived from its top-level name. Own colors SHALL come from a fixed palette readable in light and dark mode. Tag chips SHALL use the effective color everywhere, and tag rows in the tag list SHALL show it as a dot.

#### Scenario: Color a group
- **WHEN** `person` is set to green, and tags `person/alex` and `person/alex/blargh` exist without own colors
- **THEN** chips and dots of `person`, `person/alex` and `person/alex/blargh` are green everywhere

#### Scenario: Override below
- **WHEN** `person` is green and `person/alex` is set to orange
- **THEN** `person/alex` and `person/alex/blargh` are orange, and `person/sam` stays green

#### Scenario: No colors set
- **WHEN** no tag above `project/atlas` has a color
- **THEN** its chip uses the color derived from `project`, the same for every `project/…` tag

### Requirement: Set a tag color in the tag list
The tag list's context menu on a tag SHALL offer the palette colors and an entry for no own color, labeled "Inherit from <tag> (<color>)" when a tag above has a color and "Automatic" otherwise, with the current choice marked. This SHALL work for group names without their own tag too. Each change SHALL be one undo step.

#### Scenario: Back to inheriting
- **WHEN** `person` is green, `person/alex` is orange, and the user chooses "Inherit from person (Green)" for `person/alex`
- **THEN** `person/alex` and its subtags are green again, and one Undo brings orange back

### Requirement: Rename a tag
The user SHALL be able to rename a tag from the tag list's context menu and from its tag page. Subtags SHALL be renamed along, items keep their tags under the new name, and links to the tag SHALL keep working and show the new name. A rename SHALL be one undo step.

#### Scenario: Rename a group
- **WHEN** the user renames `person` to `people`, and `person/alex` and `person/sam` exist
- **THEN** the tags are `people`, `people/alex` and `people/sam` with all their items, and a link to `person/alex` now reads `people/alex`

#### Scenario: Fix a typo
- **WHEN** the user renames `projct/atlas` to `project/atlas` and no tag of that name exists
- **THEN** every item tagged `projct/atlas` is now tagged `project/atlas`, and one Undo brings the old name back

### Requirement: Merge tags on rename
Renaming a tag to a name that already exists SHALL ask for confirmation and then merge: the items of both SHALL carry the existing tag, the descriptions SHALL be joined, links to the renamed tag SHALL point to the existing one, and subtags SHALL be merged the same way. A merge SHALL be one undo step.

#### Scenario: Merge two spellings
- **WHEN** `person/al` (two tasks) is renamed to the existing `person/alex` (one page) and the user confirms
- **THEN** the two tasks and the page are tagged `person/alex`, `person/al` is gone, and links to `person/al` open `person/alex`

#### Scenario: Merge declined
- **WHEN** the user renames `person/al` to the existing `person/alex` and cancels the confirmation
- **THEN** nothing changes

### Requirement: Delete a tag
The user SHALL be able to delete a tag from the tag list's context menu and from its tag page, after a confirmation that says how many items carry it. The items SHALL lose that tag, subtags SHALL stay, and links to the deleted tag SHALL be shown as "link target deleted". A delete SHALL be one undo step.

#### Scenario: Delete a used tag
- **WHEN** the user deletes `project/old`, which three tasks carry, and confirms "Remove from 3 items"
- **THEN** the three tasks no longer carry `project/old`, the tag disappears from the tag list, and one Undo brings it back on all three
