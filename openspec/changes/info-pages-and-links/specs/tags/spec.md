# Spec Delta

## ADDED Requirements

### Requirement: Move items in the tree
The user SHALL be able to drag a task or page in the tag list onto another tag node. A plain drop SHALL replace the tag the item was dragged from with the target tag (move); a drop with ⌥ held SHALL add the target tag and keep the others (alias). A drop onto "Untagged" SHALL remove the tag the item was dragged from. Each drop SHALL be one undo step.

#### Scenario: Move a page
- **WHEN** the user drags a page from `project/atlas` onto `project/beta`
- **THEN** the page is tagged `project/beta` instead of `project/atlas` and appears only under `beta`

#### Scenario: Alias a page
- **WHEN** the user drags a page from `project/atlas` onto `project/beta` with ⌥ held
- **THEN** the page has both tags and appears under both nodes

#### Scenario: Move a task
- **WHEN** the user drags an open task from `person/alex` onto `person/sam`
- **THEN** the task is tagged `person/sam` instead of `person/alex`

### Requirement: Drop targets in the tree
Every row of a tag group (the tag itself and the items listed under it) SHALL accept drops for that tag, over its whole width including the text. While dragging, the tag group under the pointer SHALL be highlighted.

#### Scenario: Drop onto an item of a group
- **WHEN** the user drags a page over a task listed under `project/beta` and drops it there
- **THEN** `project/beta` and its items are highlighted while hovering, and the page moves to `project/beta`

#### Scenario: Drop onto the tag text
- **WHEN** the user drops an item onto the name of a tag in the tree
- **THEN** the drop is accepted for that tag

## MODIFIED Requirements

### Requirement: Tag list
The system SHALL show all tags that are assigned to at least one open task or page as a hierarchy, with the number of open tasks per tag (including descendants), and selecting a tag SHALL open its tag page, from which the task list can be filtered by that tag. Each tag node SHALL list the open tasks and pages tagged with exactly that tag as leaves, and open tasks and pages without tags SHALL be listed under "Untagged", so the tag list doubles as the tree of everything tagged.

#### Scenario: Tag hierarchy with counts
- **WHEN** two open tasks are tagged `person/alex` and one `person/sam`
- **THEN** the tag list shows `person` (3) with `alex` (2) and `sam` (1) below it

#### Scenario: Tag used only on pages
- **WHEN** the tag `topic/security` is assigned only to a page
- **THEN** it appears in the tag list with an open-task count of 0

#### Scenario: Items as leaves of the tree
- **WHEN** the user expands `project/atlas` in the tag list, and one open task, one snoozed task, one done task and two pages are tagged `project/atlas`
- **THEN** after its child tags, the two open tasks are listed (the snoozed one marked as snoozed), then the two pages; the done task is not listed; clicking a task opens it in the task editor and clicking a page opens the page

#### Scenario: Item with two tags
- **WHEN** a page is tagged `project/atlas` and `project/beta`
- **THEN** it is listed under both `atlas` and `beta`, each time marked as also living in the other tag, and not as its own leaf under `project`

#### Scenario: Untagged items
- **WHEN** a page and an open task have no tags
- **THEN** both are listed under "Untagged" at the end of the tag list

#### Scenario: Select a tag
- **WHEN** the user selects `project/atlas` in the tag list
- **THEN** the tag page of `project/atlas` opens
