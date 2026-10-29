# Spec Delta

## MODIFIED Requirements

### Requirement: Bookmarks list
The Bookmarks view of the item browser SHALL be the bookmarks list: each bookmark with its title, host, tags and the start of its description, sorted by title, filterable like any view. Clicking a bookmark SHALL open its page; ⌘-clicking SHALL open its URL in the default browser; opening the URL and deleting SHALL also be available from its context menu. Tag views and search SHALL open bookmarks the same way.

#### Scenario: Open a bookmark
- **WHEN** the user clicks "Latency dashboard" in the Bookmarks list
- **THEN** the bookmark's page opens

#### Scenario: Open the URL
- **WHEN** the user ⌘-clicks "Latency dashboard" in the Bookmarks list
- **THEN** the URL opens in the default browser

#### Scenario: Filter by tag
- **WHEN** the user filters the list by `project/atlas`
- **THEN** only bookmarks tagged `project/atlas` or below are listed

## REMOVED Requirements

### Requirement: Bookmarks in the tag tree
**Reason**: The tag tree lists tags only (specs/tags "Tag tree").
**Migration**: Click the tag in the tree to see its bookmarks in the current view, or open Bookmarks and click the tag.
