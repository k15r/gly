# Spec Delta

## MODIFIED Requirements

### Requirement: Tag list
The system SHALL show all tags that are assigned to at least one open task or page as a hierarchy, with the number of open tasks per tag (including descendants), and selecting a tag SHALL open its tag page, from which the task list can be filtered by that tag.

#### Scenario: Tag hierarchy with counts
- **WHEN** two open tasks are tagged `person/alex` and one `person/sam`
- **THEN** the tag list shows `person` (3) with `alex` (2) and `sam` (1) below it

#### Scenario: Tag used only on pages
- **WHEN** the tag `topic/security` is assigned only to a page
- **THEN** it appears in the tag list with an open-task count of 0

#### Scenario: Select a tag
- **WHEN** the user selects `project/atlas` in the tag list
- **THEN** the tag page of `project/atlas` opens
