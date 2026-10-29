# Spec Delta

## ADDED Requirements

### Requirement: Bookmarks over MCP
The system SHALL provide MCP tools to create a bookmark (title, URL, optional description and tags), update one, list bookmarks filtered by tag and text, and delete one (to the Trash). Creating a bookmark for a URL that is already bookmarked SHALL return the existing bookmark instead of a duplicate. Changes SHALL be one step in the history each and attributed to the agent.

#### Scenario: Agent saves a link
- **WHEN** an agent calls `create_bookmark` with a URL, title and the tag `project/atlas`
- **THEN** the bookmark appears in gly's Bookmarks list and on the `project/atlas` tag page

#### Scenario: Agent finds a link
- **WHEN** an agent calls `list_bookmarks` with the text "runbook"
- **THEN** it receives the bookmarks whose title, URL, description or tags contain it, with id, title, URL, description and tags
