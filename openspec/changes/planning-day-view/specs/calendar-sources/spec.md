# Spec Delta

## MODIFIED Requirements

### Requirement: Calendar refresh indicator
The system SHALL show, per calendar account, when WorkDash last received data or a change from it, so that delays in Exchange synchronization are visible. The information SHALL be available on demand (in the tooltip of the day view's refresh button) rather than taking space in the day view header.

#### Scenario: Showing last refresh
- **WHEN** the last change from the Exchange account arrived 25 minutes ago and the user hovers over the refresh button
- **THEN** the tooltip lists "Exchange: 25 min ago" for that account
