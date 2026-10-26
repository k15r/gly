# search Specification

## Purpose

Finds pages, tasks and tags by their words as you type, to open them quickly and to pick link targets, so information in WorkDash is always one shortcut away.

## Requirements

### Requirement: Full-text search
The system SHALL search titles and text of pages and tasks, and names and descriptions of tags. Matching SHALL be case-insensitive, ignore diacritics (`a` matches `ä`), and treat the last word as a prefix. Deleted items SHALL NOT be found. Results SHALL be grouped by kind (pages, tasks, tags), each group ordered by relevance, with a short excerpt showing the match.

#### Scenario: Prefix match
- **WHEN** the user searches `budg`
- **THEN** a page titled "Budget approval" is found

#### Scenario: Diacritics
- **WHEN** the user searches `uberblick`
- **THEN** a page containing "Überblick" is found

#### Scenario: Grouped results
- **WHEN** a search matches two pages, one task and one tag
- **THEN** the results show them in the groups pages, tasks and tags

### Requirement: Quick open
⌘K SHALL open a quick-open field that shows search results as the user types and opens the chosen page, task or tag page with Return. It SHALL also offer to create a new page with the typed text as title.

#### Scenario: Open a page
- **WHEN** the user presses ⌘K, types `atlas arch` and presses Return
- **THEN** the page "Atlas architecture" opens

#### Scenario: Create from quick open
- **WHEN** no page matches `Retro notes` and the user chooses "Create page"
- **THEN** a page "Retro notes" is created and opened

### Requirement: Search is fast
Search results SHALL appear within 100 ms of typing for a store with 10,000 items.

#### Scenario: Large store
- **WHEN** the store contains 10,000 items and the user types a word
- **THEN** results are shown without noticeable delay
