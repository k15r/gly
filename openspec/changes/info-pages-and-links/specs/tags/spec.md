# Spec Delta

## ADDED Requirements

### Requirement: Move pages in the tree
The user SHALL be able to drag a page in the tag list onto another tag node. A plain drop SHALL replace the tag the page was dragged from with the target tag (move); a drop with ⌥ held SHALL add the target tag and keep the others (alias). A drop onto "Untagged" SHALL remove the tag the page was dragged from. Each drop SHALL be one undo step.

#### Scenario: Move a page
- **WHEN** the user drags a page from `project/atlas` onto `project/beta`
- **THEN** the page is tagged `project/beta` instead of `project/atlas` and appears only under `beta`

#### Scenario: Alias a page
- **WHEN** the user drags a page from `project/atlas` onto `project/beta` with ⌥ held
- **THEN** the page has both tags and appears under both nodes

## MODIFIED Requirements

### Requirement: Tag list
The system SHALL show all tags that are assigned to at least one open task or page as a hierarchy, with the number of open tasks per tag (including descendants), and selecting a tag SHALL open its tag page, from which the task list can be filtered by that tag. Each tag node SHALL list the pages tagged with exactly that tag as leaves, and pages without tags SHALL be listed under "Untagged", so the tag list doubles as the tree of pages.

#### Scenario: Tag hierarchy with counts
- **WHEN** two open tasks are tagged `person/alex` and one `person/sam`
- **THEN** the tag list shows `person` (3) with `alex` (2) and `sam` (1) below it

#### Scenario: Tag used only on pages
- **WHEN** the tag `topic/security` is assigned only to a page
- **THEN** it appears in the tag list with an open-task count of 0

#### Scenario: Pages as leaves of the tree
- **WHEN** the user expands `project/atlas` in the tag list, and two pages are tagged `project/atlas`
- **THEN** both pages are listed under `atlas`, after its child tags, and clicking one opens it

#### Scenario: Page with two tags
- **WHEN** a page is tagged `project/atlas` and `project/beta`
- **THEN** it is listed under both `atlas` and `beta`, each time marked as also living in the other tag, and not as its own leaf under `project`

#### Scenario: Untagged pages
- **WHEN** a page has no tags
- **THEN** it is listed under "Untagged" at the end of the tag list

#### Scenario: Select a tag
- **WHEN** the user selects `project/atlas` in the tag list
- **THEN** the tag page of `project/atlas` opens
