# Spec Delta

## MODIFIED Requirements

### Requirement: Read one task
The system SHALL provide an MCP tool `get_task` that returns one task by id with all its fields: id, title, notes, status, priority, due date and optional time, snooze date, tags, created and modified time, and who last modified it, plus the links in its notes and its backlinks.

#### Scenario: Existing task
- **WHEN** an agent calls `get_task` with the id of an existing task
- **THEN** it receives all fields of that task

#### Scenario: Unknown or deleted task
- **WHEN** an agent calls `get_task` with an id that doesn't exist or was deleted
- **THEN** it receives a "not found" error

#### Scenario: Task with links
- **WHEN** a task's notes link to a page and another page links to the task
- **THEN** `get_task` returns the first page under links and the second under backlinks, each with id, kind and title

### Requirement: Tool descriptions guide agents
Every tool SHALL describe its purpose, its inputs with types and allowed values, and its output, in the tool list the MCP server provides. Dates SHALL be `YYYY-MM-DD` and times `HH:mm` in local time, and the descriptions SHALL say so. Descriptions of tools that take markdown SHALL explain how to write links.

#### Scenario: Agent discovers the tools
- **WHEN** an MCP client lists the tools
- **THEN** it receives `get_schedule`, `list_tasks`, `get_task`, `create_task`, `update_task`, `delete_task`, `list_tags`, `create_page`, `get_page`, `update_page`, `delete_page`, `search`, `get_context`, `get_tag_page` and `update_tag_page`, each with an input schema and description

## ADDED Requirements

### Requirement: Pages over MCP
The system SHALL provide MCP tools to create a page (required title, optional markdown text and tags), read a page by id (all fields, links and backlinks), update the given fields of a page (one change in the history per call), and delete a page (recoverable). The same validation as in the app SHALL apply, and changes SHALL be attributed to the agent.

#### Scenario: Meeting notes from an agent
- **WHEN** an agent calls `create_page` with title "Atlas sync 2026-10-27", markdown text and tag `project/atlas`
- **THEN** the page exists, appears in the app without refresh, and the history records the agent as writer

#### Scenario: Partial page update
- **WHEN** an agent calls `update_page` with only new text
- **THEN** only the text changes; title and tags stay

### Requirement: Links written by agents
Markdown sent by agents SHALL accept links as `[[Title]]` (resolved as typed links are) and in the canonical link form that tools return. Responses SHALL return markdown in the canonical form, and SHALL report links that stayed unresolved.

#### Scenario: Agent links by title
- **WHEN** an agent creates a task with notes "details in [[Atlas architecture]]" and that page exists
- **THEN** the task links to the page, and the response shows the link in canonical form

#### Scenario: Unresolved link reported
- **WHEN** an agent writes `[[Atlas roadmap]]` and no such page exists
- **THEN** the change is saved with a missing-page link, and the response lists "Atlas roadmap" as unresolved

### Requirement: Search over MCP
The system SHALL provide an MCP tool `search` that runs the full-text search with an optional kind filter (pages, tasks, tags) and a limit, returning id, kind, title and an excerpt for each result.

#### Scenario: Find notes
- **WHEN** an agent calls `search` with query `load test` and kind `page`
- **THEN** it receives matching pages with excerpts, best matches first

### Requirement: Context of an item
The system SHALL provide an MCP tool `get_context` that returns, for a page, task or tag, everything connected to it: outgoing links, backlinks and, for tags, the tagged items; each with id, kind and title.

#### Scenario: Context of a page
- **WHEN** an agent calls `get_context` for a page that links to one task and is linked from two pages
- **THEN** it receives the task under links and the two pages under backlinks

### Requirement: Tag pages over MCP
The system SHALL provide MCP tools `get_tag_page` (description and tagged items, grouped as on the tag page) and `update_tag_page` (replace the description).

#### Scenario: Describe a project
- **WHEN** an agent calls `update_tag_page` for `project/atlas` with a markdown description
- **THEN** the tag page of `project/atlas` shows that description
