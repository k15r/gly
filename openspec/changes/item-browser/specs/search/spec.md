# Spec Delta

## MODIFIED Requirements

### Requirement: Quick open
⌘K SHALL open a quick-open field that shows search results as the user types and opens the chosen page, task, bookmark, meeting page or tag page with Return. It SHALL also offer to create a new page with the typed text as title, and "Show all results", which opens All items in the browser with the typed text as filter.

#### Scenario: Open a page
- **WHEN** the user presses ⌘K, types `atlas arch` and presses Return
- **THEN** the page "Atlas architecture" opens

#### Scenario: Create from quick open
- **WHEN** no page matches `Retro notes` and the user chooses "Create page"
- **THEN** a page "Retro notes" is created and opened

#### Scenario: Show all results
- **WHEN** the user types `latency` and chooses "Show all results"
- **THEN** All items opens filtered by the text `latency`, where it can be narrowed further
