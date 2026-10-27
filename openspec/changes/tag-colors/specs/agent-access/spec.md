# Spec Delta

## MODIFIED Requirements

### Requirement: List tags
The system SHALL provide an MCP tool `list_tags` that returns existing tags with their number of open tasks and their color (own, if set, and effective), optionally filtered by a prefix, so agents can reuse existing tags.

#### Scenario: Tags below a prefix
- **WHEN** tags `person/alex` and `person/sam` exist and an agent calls `list_tags` with `prefix: "person/"`
- **THEN** both tags are returned with their open-task counts and colors

### Requirement: Tag pages over MCP
The system SHALL provide MCP tools `get_tag_page` (description, color and tagged items, grouped as on the tag page) and `update_tag_page` (replace the description and/or set or clear the tag's own color from the palette). An unknown color name SHALL be rejected with the list of allowed names.

#### Scenario: Describe a project
- **WHEN** an agent calls `update_tag_page` for `project/atlas` with a markdown description
- **THEN** the tag page of `project/atlas` shows that description

#### Scenario: Agent colors a tag
- **WHEN** an agent calls `update_tag_page` for `project/atlas` with `color: "orange"`
- **THEN** `project/atlas` and its subtags are orange in the app, and `get_tag_page` returns color "orange" as own and effective
