# Spec Delta

## MODIFIED Requirements

### Requirement: Tag list
The system SHALL show as a hierarchy all tags that are assigned to at least one open task or page, and tags with nothing assigned (such as a new subtag), with the number of open tasks per tag (including descendants); selecting a tag SHALL open its tag page. Each tag node SHALL list the open tasks and pages tagged with exactly that tag as leaves, each with the start of its text below the title, and open tasks and pages without tags SHALL be listed under "Untagged".

#### Scenario: Tag hierarchy with counts
- **WHEN** two open tasks are tagged `person/alex` and one `person/sam`
- **THEN** the tag list shows `person` (3) with `alex` (2) and `sam` (1) below it

#### Scenario: Tag used only on pages
- **WHEN** the tag `topic/security` is assigned only to a page
- **THEN** it appears in the tag list with an open-task count of 0

#### Scenario: Empty tag and finished tag
- **WHEN** the tag `person/alex/goals` has nothing assigned and the tag `person/old` is assigned only to a done task
- **THEN** `goals` appears below `alex` with a count of 0, and `old` does not appear

#### Scenario: Items as leaves of the tree
- **WHEN** the user expands `project/atlas` in the tag list, and one open task, one snoozed task, one done task and two pages are tagged `project/atlas`
- **THEN** after its child tags, the two open tasks are listed (the snoozed one marked as snoozed), then the two pages; the done task is not listed; clicking a task opens it in the task editor and clicking a page opens the page

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
- **THEN** the tag page of `project/atlas` opens

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

## ADDED Requirements

### Requirement: New subtag
The tag list (context menu of a tag) and the tag page SHALL offer to create a subtag: the user enters a name (`/` for deeper levels), the tag `<parent>/<name>` is created if it doesn't exist, and its tag page opens. An existing tag's description SHALL stay unchanged. Creating a tag SHALL be one undo step.

#### Scenario: Subtag from the tree
- **WHEN** the user chooses "New Subtag…" on `person/alex` and enters "goals"
- **THEN** the tag `person/alex/goals` exists, appears below `alex`, and its tag page is open
