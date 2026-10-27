# Proposal

## Why

Meetings are the one thing in my day WorkDash can't hold notes for. Clicking an appointment shows only its facts: not the description, not the join link, and no way to jump to it in Calendar. Prep notes, running 1:1 notes and decisions end up in pages that nothing connects to the meeting. The groundwork is there: annotations already follow an appointment through moves, renames and series splits, but only the blocking override uses them.

## What Changes

- **Richer appointment popover:**
  - the meeting description, with links clickable
  - the Teams/Zoom join link as a button, and the dial-in boilerplate folded
  - "Open in Calendar"
  - "Notes", which opens the meeting page
- **Meeting page** in the main pane, like a task page. A header shows the meeting facts and description, then a markdown document with `[[links]]`, tags and backlinks:
  - **Recurring meetings:** one ever-growing document for the whole series, which follows series splits like series overrides do. It has dated sections, newest on top. Opening it from a specific meeting goes to that meeting's section; the heading (`## Tue 3 Nov`) is added only once text is written there.
  - **One-off meetings:** one document for that meeting.
  - **History:** notes stay when a meeting is cancelled or deleted in the calendar (marked as such).
- **Day view:** appointments with notes show a small note icon.
- **Tags, search and quick open:**
  - meeting notes can be tagged
  - tagged meetings appear in the tag tree and on tag pages, next to the pages and tasks of that tag
  - search and ⌘K find meeting notes
- **Agents:**
  - `get_schedule` marks meetings that have notes
  - new tools read and write a meeting's notes, e.g. "prep notes for my 14:00 from the atlas pages"; writing appends to the meeting's dated section

Not in this change: linking a meeting with `[[…]]`, notes on appointments from hidden calendars, editing the appointment itself, bookmarks and quick capture (separate changes).

## Capabilities

### New Capabilities

- `meeting-pages`: notes documents per series or one-off meeting, the meeting page (header, description, join link, Open in Calendar), dated sections, and their life cycle when meetings change or disappear.

### Modified Capabilities

- `day-view`: the appointment popover gains description, join link, Open in Calendar and Notes; appointments with notes are marked.
- `tags`: the tag list also lists tagged meetings as leaves.
- `tag-pages`: tag pages list tagged meetings.
- `search`: full-text search and quick open include meeting notes.
- `agent-access`: `get_schedule` marks meetings with notes; tools to read and write meeting notes.

## Impact

- **Store:** migration `v5` adds a nullable `items.series_rule` column (`event_series` already holds the calendar's series key).
  - Series notes are `event_note` items with an empty `event_key` and `series_rule` pointing to the series rule.
  - One-off notes are the occurrence's `event_note` body, the same row a blocking override uses.
  - Series rules are created on demand, as for series overrides.
- **Core:**
  - meeting-note resolution (appointment → series or occurrence note) and dated-section insertion
  - commands to write notes, with the same session coalescing and undo as pages
  - indexing of meeting notes for search, links and tags
- **Calendar source:** reads the event description (`notes`) and `url` live from EventKit; they're never stored.
- **App:**
  - the popover, the meeting page and the navigation destination
  - note indicators, meetings in the tag tree, tag pages and ⌘K
- **MCP:** a `has_notes` field in `get_schedule`, and two tools.
- **Spike:** opening one specific event in Calendar (undocumented `ical://ekevent/…` URL) vs. opening Calendar on the meeting's day.
