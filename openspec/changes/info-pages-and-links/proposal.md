# Proposal

## Why

WorkDash should hold the information around my work, not only the tasks: project notes, meeting notes, notes on people, knowledge. Today only tasks exist, and their notes are plain text. Without pages and links, that information stays in other tools and WorkDash can't be "the one source for my day". Wiki-style pages, linked with `[[…]]` to each other, to tasks and to tags, with backlinks on every target, let me (and agents) build up that context in one place.

## What Changes

- **Info pages:** a new kind of item with a title, markdown text and tags.
  - The user can create, edit, delete and undo them, like tasks.
  - Pages have no folders. They're organized only by tags and links.
  - A "Pages" section in the sidebar lists all pages, most recently changed first, with a tag filter.
- **Links:** `[[` in any markdown text (pages, task notes, tag pages) opens a picker for pages, tasks and tags, and inserts a link.
  - Links survive renames of their targets.
  - Every target shows its **backlinks**: what links to it, with the surrounding text.
  - A link to a page that doesn't exist yet (`[[New topic]]`) appears as a "missing page" link. Clicking it creates the page, wiki style.
  - A link whose target was deleted shows as "link target deleted".
- **Markdown editor (Mac):**
  - The markdown stays visible and is styled lightly while typing: headings, bold and italic, lists, checklists, code, and links as clickable chips.
  - A toggle switches to a rendered read view.
  - Used for page text, task notes and tag pages.
- **Tag pages:** every tag gets a page with its own markdown description and a list of everything tagged with it or below it. Open tasks come first, then pages, then finished tasks. Clicking a tag in the sidebar opens its tag page. The tag page offers "show in task list" for the existing filter.
- **The tag tree shows everything tagged:** in the sidebar, each tag node lists its open tasks and pages as leaves, an item with several tags appears under each, and untagged items collect under "Untagged". Dragging an item onto another tag moves it, and dragging with ⌥ held adds the tag as an alias. There is no separate page hierarchy. Annotated appointments will join later.
- **Navigation:** clicking a link opens the target in the main area: a page, the task editor or a tag page. Back and forward work with ⌘[ and ⌘].
- **Search and quick open (⌘K):** full-text search across pages, tasks and tag pages, as you type, with results grouped by kind. It is used to open things and from the `[[` picker.
- **Task notes become markdown** with links, using the same editor.
- **MCP:**
  - New tools: `create_page`, `get_page`, `update_page`, `delete_page`, `search`, `get_context` (everything linked to and from an item), `get_tag_page`, `update_tag_page`.
  - Agents write links as `[[Title]]`, which WorkDash resolves, or in the canonical form returned by the tools.
  - `get_task` also returns links and backlinks.

Not in this change: link types (`prep-for`, …), properties and templates, appointment notes and links to appointments, the iPhone editor, tag rename/merge/archive UI, trigram search for inner parts of compound words, import from the Obsidian vault, a trash bin.

## Capabilities

### New Capabilities

- `info-pages`: info pages as items: fields, create, edit, delete and undo, the pages list.
- `links`: `[[…]]` links in markdown text between pages, tasks and tags, how they resolve, backlinks, missing and deleted targets, navigation.
- `markdown-editing`: the markdown editor and read view shared by pages, task notes and tag pages.
- `tag-pages`: per-tag description and the list of tagged items.
- `search`: full-text search and quick open across pages, tasks and tags.

### Modified Capabilities

- `tasks`: task notes are markdown with links (no longer "plain text in this version").
- `tags`: the tag list includes tags used only on pages and lists pages as leaves (the page tree), pages can be moved by drag and drop, and selecting a tag opens its tag page instead of filtering the task list directly.
- `agent-access`: the tool list grows (pages, search, context, tag pages), and `get_task` returns links.

## Impact

- **Store:** a `v2` migration, additive only.
  - Local-only tables that can always be rebuilt: a link index derived from markdown text, and FTS5 indexes (`unicode61`, prefix) for items and tags, as found in the store spike.
  - Info pages use the existing `items` table (`kind = 'info'`). Tag pages use the existing `tags.page_body`.
- **Core:** new commands (`createPage`, `updatePage`, `deletePage`, `updateTagPage`); link parsing and resolution on every text write; queries for pages, backlinks, tag pages and search; undo labels for pages.
- **App:** the Pages section, page view, tag page view, editor component (TextKit-based styling on `NSTextView`), quick open, navigation history, and a change to the task editor.
- **MCP:** new tools in `WorkDashMCP`. The existing tools stay compatible; `get_task` gains fields.
- **No new dependencies** planned. Markdown rendering for the read view uses `AttributedString(markdown:)` plus own block handling (decided in the design).
