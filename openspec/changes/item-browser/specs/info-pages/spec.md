# Spec Delta

## MODIFIED Requirements

### Requirement: Pages list
The Pages view of the item browser SHALL be the pages list: all pages, most recently modified first, with title, the start of the text, tags and last modification time. The sidebar SHALL show the number of pages. The list SHALL be filterable like any view, by tag including descendants among others.

#### Scenario: Recently changed first
- **WHEN** the user edits an older page
- **THEN** that page moves to the top of the pages list

#### Scenario: Filter by tag
- **WHEN** the user filters the pages list by `project`
- **THEN** only pages tagged `project/…` or `project` are shown
