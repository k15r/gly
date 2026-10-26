# Spec Delta

## MODIFIED Requirements

### Requirement: Links written by agents
Markdown sent by agents SHALL accept links as `[[…]]` (resolved as typed links are, including the `page:`, `task:` and `tag:` prefixes and the `tag/path/Title` form) and in the canonical link form that tools return. Responses SHALL return markdown in the canonical form, and SHALL report links that stayed unresolved, each with its candidates (id, kind, title, tags) when several items matched.

#### Scenario: Agent links by title
- **WHEN** an agent creates a task with notes "details in [[Atlas architecture]]" and that page exists
- **THEN** the task links to the page, and the response shows the link in canonical form

#### Scenario: Unresolved link reported
- **WHEN** an agent writes `[[Atlas roadmap]]` and no such page exists
- **THEN** the change is saved with a missing-page link, and the response lists "Atlas roadmap" as unresolved

#### Scenario: Ambiguous link with candidates
- **WHEN** an agent writes `[[Goals]]` and pages "Goals" exist under `person/alex` and `person/sam`
- **THEN** the response lists "Goals" as unresolved with both pages as candidates, and a retry with `[[person/alex/Goals]]` links the first

## ADDED Requirements

### Requirement: Links carry display names for agents
Links and backlinks in tool responses SHALL include the target's tags and a `display` name that adds the duplicate qualifier when the title is not unique. `create_page` with a title that other pages already use SHALL succeed and name those pages in its response.

#### Scenario: Two Goals pages
- **WHEN** an agent reads a page that links to the "Goals" page of `person/alex` while another "Goals" page exists
- **THEN** the link in the response has `display` "Goals · person/alex" and the page's tags
