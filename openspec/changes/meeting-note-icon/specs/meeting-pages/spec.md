# Spec Delta

## ADDED Requirements

### Requirement: Notes mark opens the notes
An appointment in the day view whose meeting has notes SHALL show a notes mark. Clicking the mark SHALL open that meeting's page directly; clicking elsewhere on the appointment SHALL keep opening its details as before. Appointments without notes SHALL show no mark.

#### Scenario: Open notes from the day view
- **WHEN** today's 1:1 has notes and the user clicks its notes mark
- **THEN** the meeting page of that 1:1 opens with its notes, and no details popover appears

#### Scenario: Click on the rest of the appointment
- **WHEN** the user clicks the title of an appointment that has notes
- **THEN** the appointment's details popover opens, as before
