# Proposal

## Why

I switch browsers regularly, so browser bookmarks never stay in one place. My links already live in gly's notes, tasks and meeting pages. gly should be the place where I keep, tag and find them, independent of the browser.

## What Changes

- **Bookmarks:** a new kind of item with a title, a URL, an optional description and tags. They live in the store like pages and tasks: history and undo, the Trash, search.
- **A bookmarks list** in the sidebar with search and a tag filter. A click opens the bookmark in the default browser.
- **From a link to a bookmark:** a web link in any text offers "Add to bookmarks" (or "Edit bookmark" when it's already one), through its icon and its context menu.
- **Bookmarks in text:** a web link whose URL is bookmarked shows a bookmark icon instead of the globe, and hovering it shows the bookmark's description and tags.
- **Inserting a bookmark:** the `[[` picker also offers bookmarks and inserts them as plain web links `[Title](https://…)`.
- **Quick capture:** Tab cycles Task → Page → Bookmark; for a bookmark, the pasted URL's page title is fetched as the default title.
- **Tag pages** list their bookmarks; **global search** finds bookmarks by title, URL, description and tags.
- **Agents** can add, update, search and delete bookmarks over MCP.

Not in this change: importing or exporting browser bookmark files, favicons, dead-link checks.

## Capabilities

### New Capabilities

- `bookmarks`: bookmarks as items, their list, adding them from links, recognizing them in text, inserting them, and showing them on tag pages and in search.

### Modified Capabilities

- `quick-capture`: the capture panel can also create bookmarks.
- `agent-access`: bookmark tools.

## Impact

- `GlyCore`:
  - migration v9 rebuilds `items` so its `kind` check allows `bookmark`, and adds a `url` column
  - bookmark commands, queries, search text and the trash
  - `LinkRef.Kind.bookmark`
- `GlyEditor`: web link runs carry whether their URL is bookmarked (icon and tooltip); the click on a web link's icon and its context menu offer add/edit.
- App:
  - the Bookmarks sidebar entry and list
  - a bookmark editor popover
  - tag page section, search and the `[[` picker
  - capture kind Bookmark, with title fetching (the app gets the outgoing-network entitlement)
- `GlyMCP`: `create_bookmark`, `update_bookmark`, `list_bookmarks`, `delete_bookmark`.
