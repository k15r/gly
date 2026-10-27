# Spec Delta

## ADDED Requirements

### Requirement: Meeting notes over MCP
`get_schedule` SHALL mark each appointment that has notes (`has_notes`). The system SHALL provide `get_meeting_notes`, which returns a meeting's notes document by appointment (as returned by `get_schedule`), with its tags, links and backlinks. It SHALL also provide `update_meeting_notes`, which appends markdown to that occurrence's dated section (or replaces the whole document when asked) and sets tags. Changes SHALL be attributed to the agent.

#### Scenario: Agent prepares a meeting
- **WHEN** an agent calls `update_meeting_notes` for tomorrow's "1:1 Alex" with "- discuss [[project/atlas/Roadmap]]"
- **THEN** the series document gets a section for tomorrow's date containing that line, the link resolves, and `get_schedule` for tomorrow marks the meeting with `has_notes`

#### Scenario: Read notes of a meeting
- **WHEN** an agent calls `get_meeting_notes` for an occurrence of a series with notes
- **THEN** it receives the whole series document, the occurrence's section heading, and the document's tags
