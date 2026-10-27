# Spec Delta

## MODIFIED Requirements

### Requirement: Tag list
The system SHALL show all tags as a hierarchy, including tags with no open items, with the number of open tasks per tag (including descendants); selecting a tag SHALL open its tag page and expand it. Each tag node SHALL list the open tasks, pages and meetings with notes tagged exactly with it as leaves, each with the start of its text and a context menu to open or delete it; open tasks and pages without tags SHALL be listed under "Untagged".

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

#### Scenario: Tagged meeting in the tree
- **WHEN** the notes of the series "1:1 Alex" are tagged `person/alex`
- **THEN** the meeting is listed under `alex` with a meeting icon, and clicking it opens its meeting page
