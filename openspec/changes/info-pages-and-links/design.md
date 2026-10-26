# Design

## Context

The current state (archived changes `mac-day-view-and-tasks`, `mcp-server`):
- **Store:** GRDB/SQLite in the app group, written only by `WorkDashAgent`. The app reads it through a read-only pool with `ValueObservation`.
- **Writes:** every write is a `Command` that `CommandHandler` runs in one transaction and one change-log batch. Undo and redo are per writer.
- **Unused so far:** the `items` table already allows `kind = 'info'`, and `tags.page_body` exists.
- **MCP:** the tool layer (`WorkDashMCP`) maps tools onto commands and queries in the agent.
- **Task notes:** a plain `TextEditor`.

The store spike measured FTS5: external content with `unicode61 remove_diacritics 2` and prefix indexes, at 3 ms or less on 10k items. It also found that views have no `rowid` and that bm25 isn't comparable across tables.

Motivation and scope are in `proposal.md`. Behavior is in the specs of this change.

## Goals / Non-Goals

**Goals:**
- **Links and backlinks are always correct after any write,** including undo, redo and agent writes, without the app doing any bookkeeping.
- **Text stays plain markdown** that agents can read and write, with no hidden structure outside the text.
- **One editor component** for pages, task notes and tag pages.

**Non-Goals:**
- Link types, properties and templates.
- Appointment links.
- The iPhone editor.
- Collaborative or merge editing: last write wins when the user and an agent edit the same text.
- Trigram search for inner parts of compound words.

## Decisions

### P1: Canonical link form is a standard markdown link with a `workdash:` URL

Stored text uses:
- `[Atlas architecture](workdash://item/<uuid>)` for pages and tasks
- `[person/alex](workdash://tag/<uuid>)` for tags

A missing-page link stays as typed: `[[Retro notes]]`.
- **Why:**
  - It's valid markdown, so agents and any renderer understand it.
  - It points to an id, so renames don't break it.
  - The label keeps the text readable without WorkDash.
- **Labels can go stale** after a rename. The app always *displays* the target's current title (P8). The stored label is refreshed whenever the source text is written again, and through the command for a rename (P3).
- **Alternatives considered:**
  - `[[uuid|Title]]`: not standard markdown, so agents and renderers would need to know it.
  - `[[Title]]` as the stored form: breaks on rename and is ambiguous.
  - A separate link table as the source of truth: text and links could drift apart, and agents would need two writes.

### P2: Derived, local-only indexes maintained by a Batch hook

A `v2` migration, additive only, adds:
- **`link_index`**: one row per link. Columns: source (`items` or `tags`, id), target kind (`item`, `tag`, `missing`), target id or missing title, and the text range for excerpts.
- **`search_index`**: an FTS5 table holding a **plain-text** copy of searchable text. Columns: owner kind and id (unindexed), title, text. Tokenizer `unicode61 remove_diacritics 2`, `prefix='2 3 4'`. Link markup is replaced by labels, so URLs and uuids aren't indexed.
- **`change_log.session`**: nullable (P6).

Both indexes are **not synced and not change-logged**, because they can be rebuilt from the text at any time. A `rebuild` function backfills them in the migration and is reused after sync later.

**Maintenance:** `Batch.insert` and `Batch.update` call `DerivedIndex.refresh(db, table, id)` whenever `title`, `body`, `name`, `page_body` or `deleted_at` of an item or tag changes. The function reparses the row and replaces its index rows. Undo and redo write through `Batch` as well, so they keep the indexes correct with no extra code. Deleted rows stay in `link_index` (backlink queries join live rows, so restoring something brings its links back) but leave `search_index`; restoring rewrites `deleted_at`, which re-indexes them. This keeps search free of joins (task 2.5).

- **Alternative considered:** SQL triggers calling a Swift function. That would need the function registered on every connection, and it would hide the dependency. The hook is explicit, and only the agent writes.

### P3: `[[Title]]` resolution and missing pages happen in the command handler

Every command that writes markdown first runs `LinkResolver.resolve(text, db)`. This covers `createTask`, `updateTask`, `createPage`, `updatePage` and `updateTagPage`.
- `[[X]]` becomes a canonical link when exactly one live page, task or tag has that title or name (case-folded like tag keys). Otherwise it stays as typed.
- The resolver returns the unresolved titles, which the MCP responses report.

Creating a page also resolves **all** missing links with exactly that title in other texts. Those texts are rewritten in the same batch, so clicking a missing link, or creating "Retro notes" from ⌘K, makes every `[[Retro notes]]` work, and a single undo reverts all of it.

On rename (`updatePage` or `updateTask` with a new title), labels of canonical links to that item are refreshed in the same batch. This keeps the stored text readable for agents. Display doesn't depend on it.

### P4: Pages reuse `items`, tags reuse `tags`

- **Pages** are `items` with `kind = 'info'`. The task-only columns stay NULL.
- **New commands:**
  - `createPage(PageDraft)`
  - `updatePage(id, PagePatch{title, body, tags, session})`
  - `deletePage(id)`
  - `updateTagPage(name, body, session)`: creates the tag row if needed, so a group node such as `person` gets one.
- **Task notes:** `TaskPatch` gains `session`.
- **Undo labels** (`label(ofBatch:)`) learn page and tag cases: `Create page "…"`, `Edit page "…" (text)`, `Delete page "…"`, `Edit tag page "…"`.
- **`get_task` and the Core task queries** keep filtering `kind = 'task'`.

### P5: Queries

- **`PageQueries`:** list with an optional tag filter (same descendant `IN` subquery as tasks), ordered by `modified_at DESC`; `page(id)`.
- **`LinkQueries`:**
  - `outgoing(source)` gives resolved targets with their current titles, or deleted or missing states.
  - `backlinks(target)` gives live sources with an excerpt cut from the source text around the stored range, about 80 characters.
- **`TagPageQueries.page(name)`:** the description plus three groups (open tasks, pages, finished tasks), using the tag's descendant filter.
- **`SearchQueries.search(query, kinds, limit)`:**
  - Tokens are quoted and the last one gets `*`.
  - Results are ranked by `bm25` within each kind, so groups are never compared by score across kinds.
  - Excerpts come from `snippet()`.
  - Results are joined to live rows.
- **Measured (task 2.5):** with 10,000 items whose texts all contain the searched words (the worst case: thousands of hits to rank), the median is 14 ms (debug build). That's within the 100 ms requirement. Realistic, sparser text is faster (spike: 3 ms or less).
- **Tag tree:** the query used by the tag list now also includes tags on live pages, with open-task counts as before.

### P6: An edit session is one undo step

The editor saves on a debounce (1 s after the last keystroke), when the text field loses focus, and when the user navigates away. Each save sends a `session` id that stays the same while one text field of one item is being edited.
- If the writer's latest live batch has the same session and item, `CommandHandler` **appends to that batch** (same batch id) instead of opening a new one.
- Reverting a batch applies its entries newest first, so one undo restores the text from before the session.
- A new session starts when the text field gains focus again.

While typing, ⌘Z goes to the text view's own undo (focus routing, L6). This gives one store-undo step per session without huge numbers of batches.

### P7: Concurrent edits: last write wins, but never under the cursor

Page and task views observe their item. An incoming change replaces the editor's text only if the editor has no unsaved local edits and isn't the first responder. Otherwise the user's next save overwrites it.

This is acceptable for a single-user tool. Both versions stay in the change log.

### P8: Editor: an `NSTextView` with a line-based styler

- **Component:** `MarkdownEditor` is an `NSViewRepresentable` around a TextKit 2 `NSTextView`.
- **Styler:** a `MarkdownStyler` restyles the edited paragraphs in `textStorage(_:didProcessEditing:)`, using line-oriented rules:
  - ATX headings
  - `**`/`__` bold, `*`/`_` italic
  - inline code and fenced code blocks (state carried across lines)
  - `- `, `* `, `1. ` lists with hanging indent
  - `- [ ]`/`- [x]` checkboxes
  - `>` quotes
  - links
- **Markdown syntax stays visible but dimmed.** The one exception is canonical links: the `](workdash://…)` part is collapsed (zero-width font plus clear color), and the label is drawn as a chip with the target's **current** title, looked up through a resolver closure.
- **Caret movement** skips collapsed ranges (`willChangeSelectionFromCharacterRange`).
- **Clicks:** ⌘-click on a chip follows it, and a click on a checkbox toggles it.
- **Web links:** `[text](https://…)` (also `http`, `mailto`, `message`) and bare `http(s)://` URLs, detected with `NSDataDetector`, are styled as links. Their syntax stays visible but dimmed; only `workdash:` URLs are collapsed into chips. ⌘-click opens them with `NSWorkspace`. The link parser ignores them for `link_index`, so they have no backlinks.
- **The `[[` trigger** opens a popover at the caret with live `SearchQueries` results plus "Create page "…"". Choosing an entry replaces `[[query` with canonical link text.
- **As built:**
  - The editor restyles the whole text on each edit, not only the edited paragraphs. That's simpler, and fast enough for page-sized texts. It's the first optimization to make if long pages lag.
  - Task notes in the task editor sheet use the editor in binding mode: they're saved with the form's Save, an explicit confirm as `specs/tasks` requires. So that save is one undo step without a session.
  - Pages and tag pages autosave with sessions.
- **Read view:** a `MarkdownReadView` (SwiftUI).
  - It splits the text into blocks (heading, paragraph, list item, checklist item, quote, code fence) and renders inline parts with `AttributedString(markdown:)`.
  - `[[X]]` is rewritten to `[X](workdash://missing/X)` first.
  - An `OpenURLAction` handles `workdash://item`, `tag` and `missing`.
  - Using system markdown parsing for inline parts avoids a dependency. Blocks are simple enough to handle ourselves.
- **Alternatives considered:**
  - A WebView with a JS editor: a heavy dependency, and not native.
  - Fully hiding all syntax, Bear style: rejected for now (user choice). The styler can grow into that later.

### P9: Navigation and views

- **`Navigation`** becomes a destination stack with back and forward. Destinations: `.day`, `.tasks`, `.pages`, `.calendars`, `.page(id)`, `.tag(name)`. ⌘[ and ⌘] move through it, and sidebar selection pushes onto it.
- **Task links** open the existing `TaskEditor` sheet rather than a destination, so they don't enter the history.
- **Sidebar:** Day, Tasks, Pages, Calendars, then Tags. Tag rows open `.tag(name)`.
- **The tag tree is the page tree** (decided while planning; no separate page hierarchy).
  - Each tag node lists, after its child tags, the live pages tagged with **exactly** that tag. Pages with several tags appear under each of them, with an "also in …" hint.
  - Pages without tags appear under "Untagged" at the end.
  - The tag page of a node still lists everything below it.
  - Data comes from one query over `item_tags` for pages (`TagQueries.tagTree` returns pages per node), so no new storage is needed.
  - **Drag and drop:** dropping a page onto a tag node sends one `updatePage(tags:)`, so it's one undo step. Plain = replace the source tag (move), ⌥ = add (alias), "Untagged" = remove the source tag.
  - **Alternative considered and rejected:** a parent/child page tree. It would be a second hierarchy next to tags, and it contradicts the "no folders" principle of the requirements.
- **`PageView`:**
  - title field
  - tag field (reused `TagField`)
  - editor or read view with an Edit/Read toggle (⌘E)
  - a backlinks section
  - a delete action in a menu
- **`TagPageView`:** the description editor plus the three groups, a "Show in Tasks" button that sets the existing tag filter, and backlinks.
- **Quick open (⌘K):** a sheet with a search field and grouped results. Arrow keys and Return open the chosen result; "Create page "…"" is the last row.
- **New Page:** ⌘⇧N anywhere. ⌘N in the pages list.

### P10: MCP tools

New tools in `WorkDashMCP`, using the same writer attribution and error style as the existing ones:
- **Pages:** `create_page(title, text?, tags?)`, `get_page(id)`, `update_page(id, title?, text?, tags?)`, `delete_page(id)`.
- **`search(query, kind?, limit?)`.**
- **`get_context(id or tag)`.**
- **Tag pages:** `get_tag_page(name)`, `update_tag_page(name, text)`.

Responses:
- They return text in the canonical form, plus `links`, `backlinks` and `unresolved` arrays of `{id, kind, title}`.
- Write tools report `unresolved` titles.
- `get_task` gains `links` and `backlinks`.

Tool descriptions say how to link: "write `[[Exact Title]]` or reuse the canonical `[label](workdash://item/<id>)` you got from a tool".

## Risks / Trade-offs

- **[Hiding the link URL in a plain `NSTextView` may feel odd: caret jumps, copy and paste]** → Collapsed ranges are skipped on selection changes. Copying copies the markdown, which is correct. If it feels bad in manual testing, fall back to showing the full link dimmed (a one-line styler change).
- **[Styling cost on long texts]** → Only edited paragraphs and the following code-fence state are restyled. Pages are expected to be short (under 50 KB).
- **[Stale labels in stored text]** → Display always uses current titles. Labels are refreshed on rename and on rewrite (P3).
- **[`[[Title]]` ambiguity when tasks share titles]** → Typed links resolve only on a unique match, otherwise they stay missing. The picker always inserts canonical links.
- **[Session coalescing merges an agent's batch by mistake]** → Coalescing requires the same writer, item and session id. Agents never send a session.
- **[Last-write-wins between user and agent on the same text]** → Rare, and both versions are in the change log. Merge UI is out of scope.
- **[FTS ranking across kinds]** → Results are grouped by kind (spike finding), never ranked across kinds.

## Migration Plan

- **`v2` migration (additive):**
  - adds `change_log.session`
  - creates `link_index` and `search_index`
  - backfills both from existing tasks and tags
- **Rollback:** the new tables and the column are additive, and the old code never reads them. **Checked in task 1.1:** an older build's `DatabaseMigrator` accepts a database with the unknown applied migration `v2` (no error; `hasBeenSuperseded` is true), so rolling back to the previous build needs no backup (`SchemaTests.testOlderMigratorOnV2Database`).
- **Existing task notes are plain text,** which is already valid markdown. Nothing to convert.
