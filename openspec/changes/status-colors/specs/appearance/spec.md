# Spec Delta

## Purpose

How gly looks across its screens: one palette of status colors with fixed meanings, and task rows built from the same chips as the task page.

## ADDED Requirements

### Requirement: Status colors
The app SHALL use one palette of status colors with fixed meanings on every screen: red for overdue and can't fit, orange for due today and warnings, blue for work needed today, purple for snoozed and back from snooze, green for done, and gray for secondary information. A status color SHALL always come with an icon or text, and the details SHALL be available as a tooltip.

#### Scenario: Same meaning everywhere
- **WHEN** a task is overdue
- **THEN** it is marked red in the day view, the task list and on its task page, and the tooltip says since when it is overdue

#### Scenario: Not by color alone
- **WHEN** a task is due today
- **THEN** its row shows an orange mark together with the text or icon "due today"

### Requirement: Task rows
Task rows (day view, task list, tag pages, search) SHALL show a bar on the left in the task's status color with the reason as a tooltip, the title, and compact chips for effort (with what's left), due date, parts and tags in the style of the task page's property chips. Hovering a row SHALL show quick actions for snoozing, setting the effort and opening the task. Appointment rows SHALL show their calendar's color as a bar on the left.

#### Scenario: Overdue task row
- **WHEN** a task with effort `M` was due yesterday
- **THEN** its row shows a red bar whose tooltip says "overdue since yesterday", and chips for "M" and yesterday's date

#### Scenario: Quick action
- **WHEN** the user hovers a task row and chooses snooze from its quick actions
- **THEN** the snooze popover of the task page opens for that task
