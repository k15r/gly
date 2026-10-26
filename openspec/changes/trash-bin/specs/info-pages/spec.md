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
