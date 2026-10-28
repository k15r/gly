# Spec Delta

## MODIFIED Requirements

### Requirement: Capture panel
The panel SHALL show one text field and, below it, a preview of what will be created (type, title, tags, due date, priority). Tab SHALL switch between Task and Page. Return SHALL create the item and close the panel without bringing gly to the front; ⌘Return SHALL create it and open it in gly with the cursor in its text; Esc SHALL close the panel without creating anything. An empty title SHALL NOT create anything.

#### Scenario: Save and keep working
- **WHEN** the user types "Call venue" and presses Return
- **THEN** a task "Call venue" exists, the panel is closed, and the previous app is still in front

#### Scenario: Save and open
- **WHEN** the user switches to Page with Tab, types "Offsite ideas" and presses ⌘Return
- **THEN** a page "Offsite ideas" is created and opened in gly with the cursor in its text

#### Scenario: Cancel
- **WHEN** the user types something and presses Esc
- **THEN** nothing is created and the panel is closed
