# quick-capture Specification

## Purpose

Lets the user add a task or page from anywhere on the Mac with one keyboard shortcut, without switching to gly.

## Requirements

### Requirement: Global capture shortcut
While gly runs, a global keyboard shortcut (default ⌃⌥Space, changeable in Settings) SHALL open the capture panel on top of whatever app is in front, with the text field focused. Pressing the shortcut while the panel is open SHALL close it. Using it SHALL NOT require Accessibility permission.

#### Scenario: Capture from another app
- **WHEN** the browser is in front and the user presses ⌃⌥Space
- **THEN** the capture panel appears above the browser with the cursor in its text field

#### Scenario: Change the shortcut
- **WHEN** the user records ⌃⇧T as the capture shortcut in Settings
- **THEN** ⌃⇧T opens the panel and ⌃⌥Space no longer does

### Requirement: Capture panel
The panel SHALL show one text field and, below it, a preview of what will be created (type, title, tags, due date, priority). Tab SHALL switch between Task and Page. Return SHALL create the item and close the panel without bringing gly to the front; ⌘Return SHALL create it and open it in gly in edit mode, with the cursor in its text; Esc SHALL close the panel without creating anything. An empty title SHALL NOT create anything.

#### Scenario: Save and keep working
- **WHEN** the user types "Call venue" and presses Return
- **THEN** a task "Call venue" exists, the panel is closed, and the previous app is still in front

#### Scenario: Save and open
- **WHEN** the user switches to Page with Tab, types "Offsite ideas" and presses ⌘Return
- **THEN** a page "Offsite ideas" is created and opened in gly in edit mode, with the cursor in its text

#### Scenario: Cancel
- **WHEN** the user types something and presses Esc
- **THEN** nothing is created and the panel is closed

### Requirement: Inline syntax
The typed text SHALL be read as: words starting with `#` are tags (`#project/atlas`); for tasks, `today`, `tomorrow`, a weekday name or abbreviation (the next such day), `3 Nov` and `2026-11-03` set the due date, and `!` (high) or `!!` (urgent) set the priority. These parts SHALL be removed from the title, and the preview SHALL show how the text was read. For pages, only tags apply; other words stay in the title.

#### Scenario: Task with tag, due date and priority
- **WHEN** on Tuesday 27 Oct the user types "Call venue tomorrow #project/atlas !"
- **THEN** the preview reads "Task · Call venue · due Wed 28 Oct · project/atlas · high", and Return creates that task

#### Scenario: Words that only look like dates
- **WHEN** the user types "Prepare friday retro" as a page
- **THEN** the page title is "Prepare friday retro" with no due date

### Requirement: Always reachable
gly SHALL keep running when its main window is closed, so the shortcut keeps working. A menu bar icon SHALL offer Quick Capture, Open gly and Quit; it can be hidden in Settings. Settings SHALL offer "Open at login".

#### Scenario: Window closed
- **WHEN** the user closes the main window and later presses the capture shortcut
- **THEN** the panel opens and the captured task is in gly when the window is reopened from the menu bar icon
