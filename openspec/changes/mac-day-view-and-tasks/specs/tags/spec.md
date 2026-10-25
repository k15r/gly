# Spec Delta

## Purpose

Groups tasks loosely with free, hierarchical tag names (for example `person/alex`, `project/atlas`), so related tasks can be found and filtered together without folders or fixed categories.

## ADDED Requirements

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

### Requirement: Tag autocomplete
While the user types a tag, the system SHALL suggest existing tags that start with the typed text, including completions of the next segment after a `/`.

#### Scenario: Prefix completion
- **WHEN** tags `person/alex` and `person/sam` exist and the user types `person/`
- **THEN** both are suggested

### Requirement: Filter tasks by tag including descendants
The system SHALL let the user filter the task list by a tag. The filter SHALL include tasks tagged with that tag or any tag below it in the hierarchy.

#### Scenario: Filter by prefix
- **WHEN** the user filters by `project` and tasks are tagged `project/atlas` and `project/atlas/logs`
- **THEN** both tasks are shown

#### Scenario: No partial segment match
- **WHEN** the user filters by `person/al` and a task is tagged `person/alex`
- **THEN** the task is not shown, because `al` is not a full segment

### Requirement: Tag list
The system SHALL show all tags that are assigned to at least one open task as a hierarchy, with the number of open tasks per tag (including descendants), and selecting a tag SHALL apply it as the task filter.

#### Scenario: Tag hierarchy with counts
- **WHEN** two open tasks are tagged `person/alex` and one `person/sam`
- **THEN** the tag list shows `person` (3) with `alex` (2) and `sam` (1) below it
