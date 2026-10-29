# Spec Delta

## Purpose

Keep web links in gly, independent of any browser: bookmarks with title, URL, description and tags, found in their own list, on tag pages and in search, recognized wherever a link to them appears in text.

## ADDED Requirements

### Requirement: Bookmarks
A bookmark SHALL have a title, a URL (http, https or mailto), an optional description and tags. Bookmarks SHALL be kept like pages and tasks: changes are undoable, deleted bookmarks go to the Trash and can be restored. Two bookmarks SHALL NOT have the same URL; adding a URL that is already bookmarked SHALL open the existing bookmark instead.

#### Scenario: Create a bookmark
- **WHEN** the user creates a bookmark "Latency dashboard" for `https://grafana.example/d/latency` with the tag `project/atlas`
- **THEN** the bookmark exists with that title, URL and tag, and ⌘Z removes it again

#### Scenario: Same URL again
- **WHEN** the user tries to add `https://grafana.example/d/latency` a second time
- **THEN** no second bookmark is created and the existing one is shown for editing

### Requirement: Bookmarks list
The sidebar SHALL offer a Bookmarks list showing each bookmark's title, host, tags and the start of its description, with a search field and a tag filter. Clicking a bookmark SHALL open its URL in the default browser; editing and deleting SHALL be available from its context menu.

#### Scenario: Open a bookmark
- **WHEN** the user clicks "Latency dashboard" in the Bookmarks list
- **THEN** the URL opens in the default browser

#### Scenario: Filter by tag
- **WHEN** the user filters the list by `project/atlas`
- **THEN** only bookmarks tagged `project/atlas` or below are listed

### Requirement: Add a bookmark from a link
A web link in a page, task, meeting or tag page text SHALL offer "Add to bookmarks" through its icon and its context menu, prefilled with the link's label as title and its URL; for a link whose URL is already bookmarked it SHALL offer "Edit bookmark" instead.

#### Scenario: Bookmark a link from notes
- **WHEN** a task's notes contain `[Runbook](https://wiki.example/runbook)` and the user chooses "Add to bookmarks" on it
- **THEN** a bookmark editor opens with title "Runbook" and that URL, and saving creates the bookmark

### Requirement: Bookmarks in text
A web link whose URL is bookmarked SHALL show a bookmark icon instead of the web link icon, and hovering it SHALL show the bookmark's title, description and tags.

#### Scenario: Hover a bookmarked link
- **WHEN** a page links to a bookmarked URL whose bookmark has the description "p99 by service"
- **THEN** the link shows a bookmark icon, and hovering it shows "p99 by service" with the bookmark's tags

### Requirement: Insert a bookmark
The `[[` picker SHALL also offer bookmarks; choosing one SHALL insert a plain web link with the bookmark's title as label and its URL.

#### Scenario: Insert from the picker
- **WHEN** the user types `[[late` in a note and chooses the bookmark "Latency dashboard"
- **THEN** the text contains `[Latency dashboard](https://grafana.example/d/latency)`

### Requirement: Bookmarks on tag pages and in search
A tag page SHALL list the bookmarks carrying that tag or a tag below it. Global search SHALL find bookmarks by title, URL, description and tags and open them like the Bookmarks list does.

#### Scenario: Tag page section
- **WHEN** the user opens the tag page of `project/atlas`
- **THEN** it lists "Latency dashboard" under Bookmarks

#### Scenario: Search by description
- **WHEN** the user searches for "p99"
- **THEN** the bookmark "Latency dashboard" is among the results
