# Spec Delta

## MODIFIED Requirements

### Requirement: Tag page content
Every tag SHALL have a tag view: the item browser filtered by the tag (items tagged with it or a tag below it), grouped by kind as open tasks (sorted like the task list, snoozed ones marked), pages (most recently modified first), meetings with notes (most recently edited first), bookmarks (by title) and finished tasks (done or dropped, most recent first, collapsed by default). Above the results it SHALL show the tag's name, color, management actions and its markdown description.

#### Scenario: Project tag page
- **WHEN** the user opens the tag page of `project/atlas`, and there are two open tasks and one page tagged `project/atlas/logs`
- **THEN** the tag page shows both tasks under open tasks and the page under pages

#### Scenario: Group tag
- **WHEN** the user opens the tag page of `person`, which is only a prefix of `person/alex` and `person/sam`
- **THEN** it shows the items of both tags, and its description can be edited like any tag page

#### Scenario: Person's meetings
- **WHEN** the user opens the tag page of `person/alex`, and the notes of "1:1 Alex" are tagged `person/alex`
- **THEN** the tag page lists "1:1 Alex" under meetings

#### Scenario: Narrow a tag page
- **WHEN** the user adds `due:week` on the tag page of `project/atlas`
- **THEN** it shows only the items due this week, still grouped by kind, with the description above

### Requirement: Open the tag page
⌥-clicking a tag in the tag tree (or clicking it outside a browser view), clicking a tag chip or a tag link SHALL open the tag's view. The tag view SHALL offer to show only one kind, like the Tasks or Pages view filtered by the tag.

#### Scenario: From a chip
- **WHEN** the user clicks the chip `project/atlas` on a task row
- **THEN** the tag page of `project/atlas` opens
