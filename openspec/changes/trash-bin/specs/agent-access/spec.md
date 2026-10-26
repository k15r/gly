# Spec Delta

## MODIFIED Requirements

### Requirement: Tool descriptions guide agents
Every tool SHALL describe its purpose, its inputs with types and allowed values, and its output, in the tool list the MCP server provides. Dates SHALL be `YYYY-MM-DD` and times `HH:mm` in local time, and the descriptions SHALL say so. Descriptions of tools that take markdown SHALL explain how to write links.

#### Scenario: Agent discovers the tools
- **WHEN** an MCP client lists the tools
- **THEN** it receives `get_schedule`, `list_tasks`, `get_task`, `create_task`, `update_task`, `delete_task`, `list_tags`, `create_page`, `get_page`, `update_page`, `delete_page`, `search`, `get_context`, `get_tag_page`, `update_tag_page`, `list_trash` and `restore`, each with an input schema and description

## ADDED Requirements

### Requirement: Trash over MCP
The system SHALL provide an MCP tool `list_trash` that lists deleted pages and tasks, most recently deleted first, each with id, kind, title, tags, an excerpt, when it was deleted and by whom (by default the last 30 days, optionally all), and a tool `restore` that restores a deleted page or task by id as the Trash does, attributed to the agent.

#### Scenario: Agent undoes its own delete
- **WHEN** an agent deleted the wrong one of two "Goals" pages, then calls `list_trash` and `restore` with that page's id
- **THEN** the page is back with its tags, the response returns it like `get_page`, and the restore is attributed to the agent

#### Scenario: Restore something that isn't deleted
- **WHEN** an agent calls `restore` with the id of a live page or an unknown id
- **THEN** it receives a not-found error that says the item is not in the trash
