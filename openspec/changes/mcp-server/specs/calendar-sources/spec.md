# Spec Delta

## MODIFIED Requirements

### Requirement: Calendar visibility and colors
The system SHALL list all available calendars grouped by account and SHALL let the user show or hide each one. Hidden calendars SHALL not contribute appointments to any view, nor to the schedule agents read over MCP. Each calendar SHALL be displayed with its system color. The visibility choice SHALL persist across app restarts.

#### Scenario: Hiding a calendar
- **WHEN** the user hides the calendar "Birthdays"
- **THEN** no birthday appointments appear in the day view, and they stay hidden after restarting WorkDash

#### Scenario: Newly added calendar
- **WHEN** a calendar is added to the system calendar
- **THEN** it appears in the calendar list and is visible by default

#### Scenario: Hidden calendar and agents
- **WHEN** the user hides the calendar "Birthdays" and an agent reads today's schedule over MCP
- **THEN** the schedule contains no birthday appointments
