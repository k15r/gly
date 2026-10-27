# Tasks

## 1. Spike and calendar data

- [ ] 1.1 Spike "Open in Calendar" (N6): try `ical://ekevent/<id>` with an Exchange and an iCloud event, and the AppleScript date fallback in the sandbox; record the result in design N6 and pick the form; verify by opening a real meeting from a throwaway build
- [ ] 1.2 Read `notes` and `url` in `EventKitSource` into `Appointment` (never into snapshots or the store) and add `MeetingDescription.parse` (N5: agenda, folded dial-in block, join URL for Teams/Zoom/Meet/Webex, bare URLs as links); verify with tests on a Teams body, a Zoom location, a plain description and none

## 2. Core

- [ ] 2.1 Migration `v5` (`items.series_rule` + index), `NotesSections` (N3: heading format, parse, insert newest-on-top, same-day append) and the resolver `MeetingNotes.document(for:)` (N2); verify with tests for "Weekly 1:1" (same document for two occurrences), "Series split", "Write today's notes", "Open an earlier meeting" (section lookup), an occurrence fallback, and the migration on a v4 store
- [ ] 2.2 Commands `saveMeetingNotes` / `appendMeetingNotes` / `deleteMeetingNotes` (N4) with on-demand rows, session coalescing, links, tags, undo labels; "has notes" = non-empty body; search kind `meeting`, `TreeLeaf`/`LinkRef` kind `meeting`, tag tree and tag page queries including meetings; verify with tests for "Nothing written", "Link from notes" (backlink on the page), "Meeting deleted in the calendar" (still found), "Delete and restore notes", a one-off with a blocking override keeping it, "Find a meeting by its notes", "Tagged meeting in the tree", "Person's meetings"

## 3. MCP

- [ ] 3.1 `has_notes` in `get_schedule`, `get_meeting_notes` and `update_meeting_notes` (N8) with descriptions; verify with MCP tests for "Agent prepares a meeting" and "Read notes of a meeting"

## 4. App

- [ ] 4.1 Popover additions (description, Join, Open in Calendar, Notes) and note icons in the day view (N7); verify manually "Description and join link", "Series notes marked"
- [ ] 4.2 `MeetingPageView` and the `meeting` destination (header, state badge, editor/read view at the right section, tags, backlinks, delete), meetings in the tag tree, tag pages and ⌘K/search (N7); verify manually "Weekly 1:1", "Write today's notes", "Open an earlier meeting", "Join and open", "Link from notes", "Tagged meeting in the tree", "Person's meetings"

## 5. End to end

- [ ] 5.1 Write `docs/manual-checks-meeting-pages.md` (neutral test data, real calendar meetings) and push it as WorkDash tasks with `scripts/manual-checks.py push`; covers a weekly meeting over two dates, a one-off deleted in the calendar, search, tags, Trash, and Claude Code preparing tomorrow's 1:1 via `update_meeting_notes`; done when `pull` reports every check passed

## Workflow follow-up

- Run `/opsx:verify meeting-pages`, then archive after the manual checks pass.
