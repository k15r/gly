# Spec Delta

## MODIFIED Requirements

### Requirement: Task page
Opening a task (from a list, the day view, the tag tree, a link, a backlink or search) SHALL show it in the main area, laid out like a page: a title row with the completion button, the title and a menu (snooze, drop, delete); a row of property chips for priority, effort (with what's left), due date, snooze and tags, each showing its value or, when empty, a faded invitation such as "+ Due", and each opening a small popover to change it; the notes in the live-preview editor; and its backlinks. Every change SHALL be saved at once as one undo step. It SHALL take part in back/forward navigation.

#### Scenario: Open a task from a link
- **WHEN** the user follows a link to a task from a page
- **THEN** the task page opens in the main area with its notes and backlinks, and ⌘[ returns to the page

#### Scenario: Task backlinks
- **WHEN** two pages link to a task
- **THEN** the task page lists both under backlinks with excerpts

#### Scenario: Set effort on the task page
- **WHEN** the user picks `L` in the effort control of the task page
- **THEN** the effort is saved at once as one undo step

#### Scenario: Set a due date by typing
- **WHEN** the user opens the due date chip and types "fri"
- **THEN** the task is due next Friday, the chip reads that date, and the change is one undo step

#### Scenario: Snooze from the chip
- **WHEN** the user opens the snooze chip of a task due Friday and chooses "Next Monday"
- **THEN** the task is snoozed until next Monday, the chip reads "Snoozed until Mon", and the due date is unchanged

#### Scenario: Empty properties
- **WHEN** a task has no due date and no effort
- **THEN** the property row shows faded "+ Due" and "+ Effort" chips
