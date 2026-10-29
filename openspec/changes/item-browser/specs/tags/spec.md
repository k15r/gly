# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: Filter tasks by tag including descendants`
- TO: `### Requirement: Filter items by tag including descendants`

## MODIFIED Requirements

### Requirement: Filter items by tag including descendants
The system SHALL let the user filter any view of the item browser by a tag. The filter SHALL include items tagged with that tag or any tag below it in the hierarchy.

#### Scenario: Filter by prefix
- **WHEN** the user filters by `project` and tasks are tagged `project/atlas` and `project/atlas/logs`
- **THEN** both tasks are shown

#### Scenario: No partial segment match
- **WHEN** the user filters by `person/al` and a task is tagged `person/alex`
- **THEN** the task is not shown, because `al` is not a full segment

### Requirement: Move items in the tree
The user SHALL be able to drag items from the browser's rows onto a tag in the tag tree. When the view is filtered by exactly one tag, a plain drop SHALL replace that tag with the target tag (move); otherwise, and with ⌥ held, it SHALL add the target tag and keep the others (alias). A drop onto "Untagged" SHALL remove the filtered tag. Each drop SHALL be one undo step.

#### Scenario: Move a page
- **WHEN** the user drags a page from Pages filtered by `#project/atlas` onto `project/beta`
- **THEN** the page is tagged `project/beta` instead of `project/atlas`

#### Scenario: Alias a page
- **WHEN** the user drags a page from Pages filtered by `#project/atlas` onto `project/beta` with ⌥ held
- **THEN** the page has both tags

#### Scenario: Move a task
- **WHEN** the user drags an open task from Tasks filtered by `#person/alex` onto `person/sam`
- **THEN** the task is tagged `person/sam` instead of `person/alex`

#### Scenario: Tag from a list
- **WHEN** the user drags a task tagged `person/alex` from the unfiltered Tasks view onto `project/atlas`
- **THEN** the task is tagged `person/alex` and `project/atlas`

## REMOVED Requirements

### Requirement: Tag list
**Reason**: The tag tree no longer lists items as leaves and gets filtering; replaced by "Tag tree".
**Migration**: Items under a tag are found by clicking the tag (it filters the current view) or on its tag view.

### Requirement: Drop targets in the tree
**Reason**: Without item leaves, only tag rows are drop targets; replaced by "Tag rows accept drops".
**Migration**: Drop onto the tag row instead of onto an item listed under it.

## ADDED Requirements

### Requirement: Tag tree
The sidebar SHALL show all tags as a hierarchy, including tags without items, with a filter field that narrows the tree to matching tags and their parents. Each tag SHALL show the number of items of the current view carrying it or a tag below it. In a browser view, tags without items there SHALL be hidden (except tags in the filter), with "Show all tags" to show them. "Untagged" SHALL filter the current view to items without tags.

#### Scenario: Tag hierarchy with counts
- **WHEN** Tasks is shown and two open tasks are tagged `person/alex` and one `person/sam`
- **THEN** the tag tree shows `person` (3) with `alex` (2) and `sam` (1) below it

#### Scenario: Counts follow the view
- **WHEN** the user switches from Tasks to Bookmarks and one bookmark is tagged `person/alex`
- **THEN** `alex` shows 1

#### Scenario: Empty tag
- **WHEN** the tag `person/alex/goals` has nothing assigned
- **THEN** in a browser view `goals` is hidden until "Show all tags" is checked, then it appears below `alex` without a count; outside a browser view it is always shown

#### Scenario: Tree follows the view
- **WHEN** the user opens Bookmarks and only `ops` and `team` carry bookmarks
- **THEN** the tag tree shows only `ops` and `team` (and their parents), each with its number of bookmarks

#### Scenario: Find a tag
- **WHEN** the user types `ale` into the tag tree's filter field
- **THEN** the tree shows `person/alex` (with `person` as its parent) and hides tags that don't match

#### Scenario: Untagged
- **WHEN** the user clicks "Untagged" in Pages
- **THEN** Pages shows the pages without tags

### Requirement: Clicks in the tag tree
In a browser view, clicking a tag SHALL set the view's tag filter to it, and ⇧-click SHALL add it to or remove it from the filter. ⌘-click, and a click outside a browser view, SHALL open the tag page. A click SHALL also expand the tag.

#### Scenario: Click filters the view
- **WHEN** the user is in Pages and clicks `project`
- **THEN** Pages shows only pages tagged `project` or below, and `project` expands, showing `atlas` below it

#### Scenario: ⇧-click adds and removes
- **WHEN** the user is in Bookmarks, clicks `project/atlas`, ⇧-clicks `ops`, then ⇧-clicks `project/atlas` again
- **THEN** Bookmarks first shows bookmarks tagged both `project/atlas` and `ops`, then only those tagged `ops`

#### Scenario: ⌘-click opens the tag page
- **WHEN** the user ⌘-clicks `project/atlas` in the tag tree
- **THEN** the tag page of `project/atlas` opens

### Requirement: Tag rows accept drops
Every tag row SHALL accept drops over its whole width including the text. While dragging, the tag under the pointer SHALL be highlighted, and a collapsed tag SHALL expand when the drag rests on it for a moment.

#### Scenario: Collapsed tag opens while dragging
- **WHEN** the user drags a page and holds it over the collapsed tag `project` for about half a second
- **THEN** `project` expands, so the page can be dropped onto one of its child tags

#### Scenario: Drop onto the tag text
- **WHEN** the user drops an item onto the name of a tag in the tree
- **THEN** the drop is accepted for that tag
