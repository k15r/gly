# Spec Delta

## MODIFIED Requirements

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
