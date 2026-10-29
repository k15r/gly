# Design

## Context

- **Items** hold pages (`info`), tasks, meeting notes (`event_note`) and `local_event`. Their `kind` column has a `CHECK (kind IN (…))` from migration v1. Tags, the change log, the Trash (`TrashQueries`), the search index (`DerivedIndex`) and MCP all work on items.
- **Web links** are parsed by `MarkdownStyler` (`.webLink(url:)` runs with a globe decoration in the label's kerning space) and by `LinkParser.plainText`. A plain click on a link chip follows it on rendered lines (live-preview L3).
- **The `[[` picker** gets suggestions from `WikiModel.suggestions`; `LinkRef.Kind` is page, task, tag, meeting.
- **Quick capture** parses with `CaptureParser` into `CaptureDraft` with `CaptureKind` task or page.
- **Entitlements:** the app is sandboxed without network access; the agent has `network.server`.

## Goals / Non-Goals

**Goals:**
- Bookmarks are first-class items: tags, search, the Trash, history and MCP come along instead of being rebuilt.
- Texts stay portable: links are plain markdown web links.

**Non-Goals:**
- Browser bookmark import/export, favicons, link checking, reading lists.
- Syncing with browsers.

## Decisions

### B1: Bookmarks are items of kind `bookmark`

Migration v9 rebuilds `items`:
1. create `items_new` with the same columns plus `url TEXT`, and `kind` checked against `info, task, event_note, local_event, bookmark`
2. copy all rows
3. drop `items`, rename `items_new`
4. recreate the indexes and the `live_items` view

This runs inside the migration transaction, with GRDB's deferred foreign key check, since `item_tags`, `task_work` and `task_parts` reference `items`.

A bookmark has `title`, `url`, `body` (the description, markdown) and tags through `item_tags`. A partial unique index `items_bookmark_url ON items(url) WHERE kind = 'bookmark' AND deleted_at IS NULL` prevents duplicates. URLs are normalized before storing (scheme and host lowercased, a trailing slash removed from a bare host).

- **Alternative: a separate `bookmarks` table.** Rejected: tags, the Trash, search, history, undo labels and MCP would all need bookmark-specific copies.
- **Alternative: pages with a URL.** Rejected: every page query would have to exclude them, and they'd show up in the pages list.

### B2: Commands and queries

- `createBookmark(BookmarkDraft)` returns the existing id with `changed: false` when the URL is already bookmarked.
- `updateBookmark(id, BookmarkPatch)` changes title, url, description or tags.
- `deleteBookmark(id)` soft-deletes; `restore` already works for items.
- `BookmarkQueries.list(tag:, text:)`, `bookmark(byURL:)` and `bookmarks(byURLs:)` (for the editor's lookups).
- `DerivedIndex` gives bookmarks the search text title + URL + description, and `LinkRef.Kind.bookmark` lets search and the picker show them.
- Undo labels read "Add bookmark …", "Edit bookmark …" and "Delete bookmark …".

### B3: Bookmarks in the editor

- **Appearance:** the editor's appearance callback gets a second lookup, `bookmark(for url) -> BookmarkInfo?`. A `.webLink` run whose URL is bookmarked gets the `bookmark` symbol instead of `globe`, plus a tooltip "Title — description · #tags". The tooltip is the hover popup: it's native, needs no extra window, and fits the "details in tooltips" rule. A richer popover can follow later.
- **The icon is a button:** a click on the drawn icon (the hidden `[` before the label) opens the bookmark editor popover, to add or to edit. This also works on rendered lines, where a click on the label follows the link.
- **Context menu:** web links get "Add to bookmarks…" or "Edit bookmark…", plus "Copy link".

### B4: The bookmark editor

A popover with title, URL, description (a plain multi-line text field) and tags (`TagField`). "Save" sends create or update. When the URL is already bookmarked, it shows that bookmark instead (spec "Same URL again").

### B5: The list, tag pages, search and picker

- **Sidebar list:** a "Bookmarks" entry with a count, and a list with a search field and a tag filter. Each row has a `bookmark` icon, the title, the host, tag chips and the first line of the description. A click opens the URL with `NSWorkspace.open`; the context menu has Edit, Copy URL, Delete.
- **Tag pages:** a "Bookmarks" section.
- **Search:** results of kind bookmark open the URL; a modifier click opens the editor.
- **The `[[` picker:** offers bookmarks with the `bookmark` symbol and inserts `[title](url)`.

### B6: Quick capture

`CaptureKind.bookmark`: the first token that parses as a URL is the URL, `#tags` are tags, and the remaining words are the title. The preview shows "Bookmark · <title or fetching…> · host · tags". When no title is typed, the app fetches the page with `URLSession` (a 5 s timeout), reads `<title>` from the first 64 KB, and falls back to the host. The app gets `com.apple.security.network.client`. ⌘Return opens the bookmark editor instead of a page.

### B7: MCP

- `create_bookmark {url, title?, description?, tags?}`: without a title it uses the host, since the agent can't fetch; agents usually know the title. It returns the existing bookmark for a known URL.
- `update_bookmark {id, …}`, `list_bookmarks {tag?, text?, limit?}`, `delete_bookmark {id}`.
- Bookmark results are `{id, title, url, description, tags, created_at, modified_at, modified_by}`.

## Risks / Trade-offs

- **[Rebuilding `items`]** It's the biggest table, and other tables point to it. → One transaction with a deferred FK check, plus a migration test on a database with tasks, pages, meeting notes, tags, work and links, checking counts, links, the search index and a foreign key check afterwards.
- **[URL matching]** `https://x.com/a` vs `https://x.com/a/` vs `http://` count as different. → Normalization covers case and a bare host's trailing slash only, so paths stay exact. Good enough to start.
- **[Network access in the app]** New entitlement. → Used only for fetching a typed URL's title in quick capture.
