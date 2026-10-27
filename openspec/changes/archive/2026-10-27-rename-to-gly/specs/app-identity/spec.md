# Spec Delta

## Purpose

Defines the product's name and identity, and how it takes over data, settings and links from its previous name, WorkDash, without losing anything.

## ADDED Requirements

### Requirement: Product name
The product SHALL be named "gly", written in lowercase, everywhere it shows its name: app bundle, Dock, Finder, menu bar item, window and menu titles, Settings, alerts, and the name the MCP server reports to agents.

#### Scenario: Name in the system
- **WHEN** the user opens the app and looks at the Dock, the menu bar item and an agent's MCP server list
- **THEN** each shows "gly"

### Requirement: Take over data from WorkDash
On the first start, when gly has no store of its own and a WorkDash store exists, gly SHALL copy the WorkDash store (pages, tasks, tags, meeting notes, trash and history) and the shared settings (working hours, effort sizes, hidden calendars, agent access incl. its token) into its own storage before showing anything. The WorkDash files SHALL stay unchanged. If gly already has a store, nothing SHALL be copied.

#### Scenario: First start with WorkDash data
- **WHEN** gly starts for the first time on a Mac where WorkDash holds 16 open tasks, 15 pages and custom working hours
- **THEN** gly shows the same 16 open tasks, 15 pages and working hours, and the WorkDash database still exists unchanged

#### Scenario: Later starts
- **WHEN** gly starts again after the takeover and the user has made changes in gly
- **THEN** nothing is copied again and the changes stay

### Requirement: Links keep working
Links between pages, tasks, tags and meetings SHALL keep pointing to the same targets after the rename. Link URLs SHALL use the `gly://` scheme; URLs with the old `workdash://` scheme, in taken-over texts or pasted later, SHALL be read like `gly://` URLs.

#### Scenario: Taken-over link
- **WHEN** a page taken over from WorkDash linked to a task
- **THEN** in gly the link still opens that task, and the page text now stores a `gly://` link

#### Scenario: Pasted old link
- **WHEN** the user pastes `[Plan](workdash://item/<id>)` into a page
- **THEN** it is shown and followed like a link to that item

### Requirement: One store writer
gly SHALL never write to the WorkDash store, and SHALL work normally without WorkDash being present. Stopping the WorkDash agent is a one-time manual step of the switch-over, done before gly's first start.

#### Scenario: WorkDash stopped before the switch
- **WHEN** the WorkDash agent was stopped and gly starts for the first time
- **THEN** gly takes over the data, works with its own store, and WorkDash's store stays as it was
