# Design

## Context

- **Appointments** come live from EventKit (`EventKitSource` → `Appointment`) and are never stored. `Appointment` has title, times, location, organizer, attendees and identity (`calendar/baseID@originalStart`), but not the description (`EKEvent.notes`) or `url`.
- **Annotations:** an annotated occurrence is an `event_note` item: `title`, `body` (empty so far), `event_key` (occurrence), `event_series` (the calendar's series key), snapshot columns, `event_state` (active/cancelled/gone/ambiguous) and `blocking`. `AnnotationMatcher` and `AnnotationReconciler` keep them attached through moves and splits.
- **Series overrides** live in `series_rules` (calendar, title, organizer, `base_ids` that grow on splits) and match via `SeriesRule.matches`.
- **Items** get tags, link and search indexing (`DerivedIndex` over every item), trash and undo for free. Search filters by kind (`info`, `task`, `tag`).
- **The day view popover** (`AppointmentDetails`) shows facts only. Task pages show how an item renders as a page (`TaskPageView`: header + `WDMarkdownEditor`/read view + tags + backlinks).

Motivation is in `proposal.md`, behavior in this change's specs.

## Goals / Non-Goals

**Goals:**
- **Reuse:** meeting notes are items, so links, tags, search, trash, undo and MCP attribution work as for pages.
- **One resolver** from an appointment to its notes document, used by the day view, the meeting page and MCP.

**Non-Goals:**
- Linking meetings with `[[…]]`.
- Storing descriptions.
- Editing calendar events.
- Notes for hidden calendars.

## Decisions

### N1: Where notes live

- **Series document:** an `event_note` item with `event_key = NULL`, `series_rule = <series_rules.id>` (new nullable column, migration `v5`), `title` = the series title, and snapshot columns from the occurrence it was created from.
  - Writing the first note of a recurring meeting creates the series rule if needed (the same code path as a series override), then the item.
  - Because the series rule follows splits (`base_ids`, title + organizer continuation), the document follows too.
- **One-off document:** the occurrence's `event_note` body, the same row a blocking override uses. It's created on demand like an override, with `blocking = NULL`.
- **"Has notes":** a live `event_note` whose body isn't empty. Rows that exist only for a blocking override are not notes. Search and tag queries filter on non-empty bodies.

**Alternative considered:** a `notes` column on `series_rules`. Rejected: rules aren't items, so they would have no tags, links, search, trash or undo.

**Alternative considered:** reusing `event_series` for the rule id. Rejected: it already holds the calendar's series key, which existing rows depend on.

### N2: Resolver `MeetingNotes.document(for appointment, db)`

Returns `(kind: .series(ruleID?) | .occurrence(key), itemID?, sectionDate)`:
- **Recurring appointment:** the series rule that `matches` it, and that rule's notes item, if any.
- **Otherwise:** the occurrence's `event_note` by key, after reconciliation, so moves are already adopted.
- **Nothing exists yet:** the IDs are nil. The page shows an empty editor, and the first save creates the rows (spec "Nothing written").

### N3: Dated sections (pure `NotesSections`)

- A section heading is `## <EEE d MMM>` in a fixed English format (`## Tue 3 Nov`), plus the year when it's not the current year. A fixed format keeps parsing independent of the system language. A heading without a year belongs to the current year, or to the year before when that would put it more than six months in the future.
- **Parsing:** headings that parse as a date in that format form sections. Other headings are ordinary markdown inside a section.
- **`insert(text, for date, into body)`:** if a section for the date exists, append to it. Otherwise insert a new section above the first older section (newest on top), or at the top.
- **The page** opens the editor with the cursor in the meeting's section. If the section doesn't exist yet, its heading is already in the editor's text (placed newest-on-top), but it's stored only once something is typed, because the editor saves changes only. Opening and leaving without typing stores nothing.
- **Agents** use `insert` as well.

### N4: Commands

- **`saveMeetingNotes(target, body, tags?, session)`:** `target` is a series rule or an occurrence snapshot. It creates rows on demand (N1), coalesces per session like `updatePage`, resolves links, and replaces tags.
- **`appendMeetingNotes(target, date, markdown)`:** for MCP; uses `NotesSections.insert`.
- **Deleting:** reuses `deletePage`-like logic (`deleteMeetingNotes(itemID)`).
  - For a one-off row that also has a blocking override, it clears the body and tags instead of tombstoning, so the override stays (spec "Delete meeting notes").
  - The Trash entry then shows the notes via the change log revert.
- **`updateMeetingNotes(id, body?, tags?, session)`:** changes existing notes by id. The page uses it when opened from search, tags or backlinks, and the tag tree uses it for drags.
- **Undo labels:** "Edit notes “1:1 Alex”", "Delete notes “1:1 Alex”".

### N5: Description and join link (live, never stored)

- **Data:** `Appointment` gains `notes: String?` and `url: URL?` from EventKit. They're not part of `AppointmentSnapshot` and never written to the store.
- **`MeetingDescription.parse(notes, location, url)`:** returns the agenda text, a folded dial-in block, and a join URL.
  - The join URL is the first `teams.microsoft.com/l/meetup-join`, `zoom.us/j`, `meet.google.com` or `webex` link in location, url or notes.
  - The dial-in block starts at the first `____…` separator line or a "Microsoft Teams" heading.
  - Bare URLs in the agenda become links.

### N6: No "Open in Calendar"

Dropped after a first look. Opening one exact event needs an undocumented `ical://ekevent/…` URL, and the fallback only activates Calendar. With the description, the folded dial-in block and Join in the details, it adds nothing, so the details stay without it.

### N7: App

- **`Navigation.Destination.meeting(MeetingRef)`:** `MeetingRef` is the notes item id, or an appointment identity plus date when no notes exist yet.
- **`MeetingPageView`:** a header (facts, description, Join, a state badge for cancelled or gone), then the editor or read view with the `TaskPageView` patterns (session saves, link menu, tags, backlinks).
- **Popover:** `AppointmentDetails` adds the description (attendees folded), Join and Notes.
- **Day view:** a note icon from `MeetingMarksModel`, one observation of the occurrence keys and series rules that have notes (`MeetingNotes.marks`), shared by all rows.
- **Tag tree:** untagged meeting notes appear under "Untagged". Dragging meeting notes onto tags changes their tags (move, ⌥ alias, Untagged removes), like pages and tasks.
- **Tag tree, tag pages and ⌘K/search:** a `meeting` kind with a calendar icon (`calendar`), using `TreeLeaf.kind = .meeting` and `SearchResults.meetings`. `LinkRef.Kind` gains `meeting` for backlinks and search only. `[[` doesn't offer meetings (non-goal), and `LinkParser` doesn't change.

### N8: MCP

- **`get_schedule`:** `has_notes` per appointment.
- **`get_schedule`** also gains the identity fields per appointment: `calendar_id`, `base_id`, `original_start`. It didn't return them before; this was found while implementing.
- **`get_meeting_notes(calendar_id, base_id, original_start)`:** takes those fields. Returns `{title, kind: series|occurrence, text, section, tags, links, backlinks}`.
- **`update_meeting_notes(... , text, mode: append|replace, tags?)`:** append inserts into that occurrence's dated section (N3).

## Risks / Trade-offs

- **[A recurring meeting without a matching rule after an unusual split]** → The resolver falls back to occurrence notes and the page shows a hint. Reconciliation keeps adopting splits as it does for overrides.
- **[Descriptions contain sensitive text]** → Shown only, never stored or indexed. Search covers notes only.
- **[Large series documents]** → Plain text in one row; years of weekly notes are a few hundred KB, fine for SQLite and the editor.

## Migration Plan

`v5`: `ALTER TABLE items ADD COLUMN series_rule TEXT` plus an index. Existing rows get NULL, so nothing changes until notes are written. An older app ignores the column.
