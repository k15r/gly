# tag-pages Specification

## Purpose

Turns every tag into a page of its own (for a project, a person, a topic) with a free description and everything that carries the tag, so a tag is a natural place to collect context.

## Requirements

### Requirement: Tag page content
Every tag SHALL have a tag page showing the tag's name, its markdown description, and the items tagged with it or with a tag below it, grouped as: open tasks (sorted like the task list, snoozed ones marked), pages (most recently modified first), meetings with notes (most recently edited first), and finished tasks (done or dropped, most recent first, collapsed by default).

#### Scenario: Project tag page
- **WHEN** the user opens the tag page of `project/atlas`, and there are two open tasks and one page tagged `project/atlas/logs`
- **THEN** the tag page shows both tasks under open tasks and the page under pages

#### Scenario: Group tag
- **WHEN** the user opens the tag page of `person`, which is only a prefix of `person/alex` and `person/sam`
- **THEN** it shows the items of both tags, and its description can be edited like any tag page

#### Scenario: Person's meetings
- **WHEN** the user opens the tag page of `person/alex`, and the notes of "1:1 Alex" are tagged `person/alex`
- **THEN** the tag page lists "1:1 Alex" under meetings

### Requirement: Edit the tag description
The user SHALL be able to edit a tag page's description with the markdown editor, including `[[` links. A description for a group node such as `person` SHALL create the tag `person` if it doesn't exist yet.

#### Scenario: Describe a person
- **WHEN** the user writes a description on the tag page of `person/alex` and closes it
- **THEN** the description is saved and shown the next time the tag page opens

### Requirement: Open the tag page
Clicking a tag (in the sidebar, on a tag chip, or via a tag link) SHALL open its tag page. The tag page SHALL offer to show its tasks in the task list, and its pages in the pages list, with the tag as filter.

#### Scenario: From a chip
- **WHEN** the user clicks the chip `project/atlas` on a task row
- **THEN** the tag page of `project/atlas` opens

### Requirement: Tag color on the tag page
The tag page SHALL show the tag's name in its effective color, with a small color swatch next to it that opens the same color menu as the tag list and whose tooltip says whether the color is the tag's own, inherited from a tag above, or automatic.

#### Scenario: Inherited color shown
- **WHEN** `person` is green and the user opens the tag page of `person/alex`, which has no own color
- **THEN** the name is green, the swatch's tooltip says "inherited from person", and choosing orange in its menu makes `person/alex` orange

### Requirement: Manage a tag from its tag page
The tag page SHALL offer to rename the tag and to delete it, with the same behavior as in the tag list (subtags renamed along, merge after confirmation on an existing name, delete after confirmation). After a rename or merge, the tag page SHALL show the tag under its new name; after a delete it SHALL close.

#### Scenario: Rename from the tag page
- **WHEN** the user renames `projct` to `project` on its tag page
- **THEN** the tag page now shows `project` with the same items and description
