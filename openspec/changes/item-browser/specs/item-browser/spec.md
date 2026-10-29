# Spec Delta

## Purpose

One place to find items: tasks, pages, bookmarks and meeting notes in one list, narrowed down by what is known about them (kind, tags, status, dates, effort, priority, author, text), with preset and saved views in the sidebar.

## ADDED Requirements

### Requirement: Item browser and preset views
The sidebar SHALL offer the views All items, Tasks, Pages, Bookmarks and Meetings, all showing the same item browser with a preset filter: no filter, open and snoozed tasks, pages, bookmarks, meetings with notes. A view's filter, grouping and sorting SHALL be changeable; the view SHALL keep the changes while the app runs and offer to reset them to the preset.

#### Scenario: Tasks view
- **WHEN** the user opens Tasks
- **THEN** the browser lists open and snoozed tasks in task-list order, and the filter bar shows the kind and status filters as chips

#### Scenario: Back to a view
- **WHEN** the user adds `#project/atlas` in Tasks, opens a task and goes back
- **THEN** Tasks still shows only tasks tagged `project/atlas`, and "Reset" brings back the preset

### Requirement: Filter bar
The browser SHALL show the active filters as removable chips and accept typed tokens:
- `is:task|page|bookmark|meeting`
- `#tag` (the tag or below; several must all match) and `-#tag` (excluded)
- `status:open|snoozed|done|dropped`
- `due:overdue|today|week|none`
- `prio:<priority>`, `effort:<size>`
- `changed:today|7d|30d`, `by:me|agent`
- `host:<host>`
- `untagged`

Other words SHALL search the items' titles and texts. Each kind of filter SHALL also be offered from an add-filter menu.

#### Scenario: Typed tokens
- **WHEN** the user types `is:task #project/atlas due:week review` in All items
- **THEN** the list shows tasks tagged `project/atlas` or below, due within 7 days, whose title or text contains "review", and the filter bar shows three chips plus the text

#### Scenario: Exclude a tag
- **WHEN** the user adds `-#ops` to Bookmarks
- **THEN** bookmarks tagged `ops` or below are no longer listed

#### Scenario: Agent changes
- **WHEN** the user filters All items with `by:agent changed:today`
- **THEN** the list shows the items an agent changed last today

### Requirement: Refine by tags
Above the results, the browser SHALL show the tags that occur among the current results, most frequent first, each with the number of results carrying it or a tag below it, leaving out tags already in the filter. Clicking one SHALL add it to the filter.

#### Scenario: Who is involved
- **WHEN** Tasks is filtered by `#project/atlas` and four of its tasks are tagged `person/alex`, two `person/sam`
- **THEN** the refine row shows `person/alex 4` before `person/sam 2`, and clicking `person/alex` leaves the four tasks

### Requirement: Grouping and sorting
The browser SHALL group results by nothing, kind, due date (overdue, today, this week, later, no due date), status or tag (the next level below a filtered tag, else top-level tags), and sort by relevance (when searching text), last change, due date, title or task-list order. Each preset view SHALL have a sensible default: Tasks in task-list order, Pages and All items by last change, Bookmarks by title, tag views grouped by kind.

#### Scenario: Group by due date
- **WHEN** the user groups Tasks by due date
- **THEN** the overdue tasks come first under "Overdue", then "Today", "This week", "Later" and "No due date"

### Requirement: Item rows
Every result SHALL be one row with the kind's icon, the title, the start of its text, its tags (on one line: as many as fit, then "+N" showing the others on hover) and, depending on the kind, its task chips and status bar, the bookmark's host, or the last change. A click SHALL open the item's page; ⌘-click SHALL open its link when it has one (a bookmark's URL) and otherwise its page. Rows SHALL be draggable onto tags in the tag tree, and offer the item's actions in their context menu.

#### Scenario: Open a bookmark from the browser
- **WHEN** the user clicks a bookmark in All items, then ⌘-clicks it
- **THEN** the first click opens its page, the ⌘-click its URL in the default browser

#### Scenario: Same layout for every kind
- **WHEN** a task, a page and a bookmark are listed one below the other
- **THEN** each shows its title on the first line, its metadata (task chips, the bookmark's host, the last change) on the left of the second line with its tags right-aligned on the same line, and the start of its text on the third line

#### Scenario: Many tags
- **WHEN** a task has eight tags and its row has room for three
- **THEN** the row shows the first three tags and "+5", and hovering "+5" shows the other five

#### Scenario: Task row keeps its actions
- **WHEN** the user hovers a task row in the browser
- **THEN** it shows its status bar and the snooze, effort and open buttons as in the day view

### Requirement: Saved views
The user SHALL be able to save the current filter, grouping and sorting as a named view, which appears in the sidebar below the preset views and can be renamed and deleted there. Saved views SHALL be kept in gly's store like other data: across restarts, undoable, and available to agents.

#### Scenario: Save a view
- **WHEN** the user filters Tasks by `#project/atlas due:week`, chooses "Save View…" and names it "Atlas this week"
- **THEN** "Atlas this week" appears in the sidebar and opens with that filter, also after restarting gly

### Requirement: Create from a view
The browser SHALL offer creating an item of the view's kind (New Task, New Page, New Bookmark; a menu in All items); a new item SHALL get the view's tag filters as tags.

#### Scenario: New task in a tag view
- **WHEN** the user chooses New Task in Tasks filtered by `#project/atlas`
- **THEN** the new task form starts with the tag `project/atlas`

### Requirement: Browser is fast
Changing a filter SHALL update the results within 100 ms for 5,000 items, and changes from anywhere (the app, agents) SHALL appear without reloading.

#### Scenario: Agent adds a task
- **WHEN** an agent creates a task tagged `project/atlas` while Tasks is filtered by `#project/atlas`
- **THEN** the task appears in the list without any action
