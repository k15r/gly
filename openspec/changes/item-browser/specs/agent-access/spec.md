# Spec Delta

## ADDED Requirements

### Requirement: Views over MCP
The system SHALL provide MCP tools to list the views (the preset views and the saved ones, each with its name, filter in the token syntax, grouping and sorting), create a saved view, change one and delete one. Preset views SHALL be listed but not changeable. Each change SHALL be one step in the history, attributed to the agent, and appear in the sidebar at once.

#### Scenario: Agent saves a view
- **WHEN** an agent calls `create_view` with the name "Atlas this week" and the filter `is:task #project/atlas due:week`
- **THEN** "Atlas this week" appears under Saved Views in the sidebar, and ⌘Z in gly removes it

#### Scenario: Agent changes and deletes a view
- **WHEN** an agent calls `update_view` with a new filter for "Atlas this week", then `delete_view`
- **THEN** the view first shows the new filter, then disappears from the sidebar

#### Scenario: Preset views are read-only
- **WHEN** an agent calls `update_view` or `delete_view` for the preset "Tasks"
- **THEN** the call fails with a message that preset views can't be changed

### Requirement: Items over MCP
The system SHALL provide an MCP tool `list_items` that returns the items matching a filter in the token syntax of the browser, or the filter of a view given by id, with an optional sort and limit; each item with its id, kind, title, tags, last change and, depending on the kind, its task fields or its URL.

#### Scenario: Agent runs a view
- **WHEN** an agent calls `list_items` with the id of "Atlas this week"
- **THEN** it receives the same items the view shows in gly, in the view's order

#### Scenario: Agent filters directly
- **WHEN** an agent calls `list_items` with `is:bookmark #ops`
- **THEN** it receives the bookmarks tagged `ops` or below, with their URLs
