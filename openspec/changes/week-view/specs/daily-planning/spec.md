# Spec Delta

## ADDED Requirements

### Requirement: Week overview
The day view SHALL show a strip with one entry per working day of the displayed day's week. Each entry for today or a later day SHALL show the work needed that day and the free time that day, as in that day's planning header, and SHALL be marked as short in the warning color when the needed work exceeds the free time. Past days SHALL be shown dimmed without numbers. Clicking an entry SHALL open that day.

#### Scenario: Overbooked Tuesday
- **WHEN** it is Monday and Tuesday's forecast needs 9 hours with 6 hours free
- **THEN** Tuesday's entry shows "9h / 6h" marked in the warning color

#### Scenario: Jump to a day
- **WHEN** the user clicks Thursday in the strip
- **THEN** the day view shows Thursday, and Thursday is highlighted in the strip

#### Scenario: Past days
- **WHEN** it is Wednesday
- **THEN** Monday and Tuesday are shown dimmed without numbers
