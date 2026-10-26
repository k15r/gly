# Spec Delta

## MODIFIED Requirements

### Requirement: Create, edit and delete pages
The system SHALL let the user create a page, change its title, text and tags, and delete it. Changes SHALL be saved without an explicit save step while editing. A deleted page SHALL disappear from all views and stay recoverable from the Trash.

#### Scenario: Edit text
- **WHEN** the user types in a page's text and then switches to another page
- **THEN** the change is saved and still there after restarting WorkDash

#### Scenario: Delete a page
- **WHEN** the user deletes a page
- **THEN** it disappears from the pages list, search and tag pages, and appears in the Trash

### Requirement: Pages list
The system SHALL provide a pages list showing all pages, most recently modified first, with title, the start of the text, tags, last modification time and creation date. The sidebar SHALL show the number of pages. The list SHALL be filterable by tag (including descendants).

#### Scenario: Recently changed first
- **WHEN** the user edits an older page
- **THEN** that page moves to the top of the pages list

#### Scenario: Filter by tag
- **WHEN** the user filters the pages list by `project`
- **THEN** only pages tagged `project/…` or `project` are shown

### Requirement: Duplicate page titles
Several pages SHALL be allowed to have the same title (for example a "Goals" page per person). Creating or renaming a page to a title that is already used SHALL succeed; the pages are told apart by their tags (see links "Duplicate titles are distinguishable"). In the pages list, which shows all tags, the tag that tells them apart SHALL be emphasized instead of repeated after the title, and pages with identical tags are told apart by their creation dates.

#### Scenario: Profile pages per person
- **WHEN** the user creates a page "Profile" tagged `person/alex` and another page "Profile" tagged `person/sam`
- **THEN** both pages exist, and the pages list shows "Profile" twice, with `person/alex` and `person/sam` emphasized among their tags
