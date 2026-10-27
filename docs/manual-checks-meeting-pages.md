# Manual checks: meeting-pages

Build and run: `scripts/build.sh && open build/Build/Products/Debug/gly.app`.
Neutral test data only (no real names in notes or tags; your real calendar meetings are fine to click). Setup: a recurring meeting this week and next (e.g. a weekly), a one-off meeting with a Teams link, a page "Roadmap" tagged `project/atlas`.

## A. Details popover (task 4.1)

- [x] A1 Click a Teams meeting → the details show the description with clickable links, "Teams details" folded, attendees folded to "N attendees", "Join Teams" and "Add Notes" ("Description and join link").
- [x] A2 After writing notes for a recurring meeting (B1), every occurrence of it shows a small note icon in the day view, also on other days; the popover says "Notes" instead of "Add Notes" ("Series notes marked").

## B. Meeting page (task 4.2)

- [x] B1 "Add Notes" on this week's occurrence of the recurring meeting → the meeting page opens in edit mode with the header (time, calendar, organizer, attendees, description, Join), the cursor under `## <today's meeting date>`; type "agreed on scope" → saved ("Write today's notes").
- [x] B2 Open next week's occurrence → same document; a new heading for that date appears above only once you type; leave without typing → nothing stored ("Weekly 1:1", "Nothing written").
- [x] B3 Reopen this week's occurrence → the cursor is in this week's section ("Open an earlier meeting").
- [x] B4 In the notes type `[[project/atlas/Roadmap]]` → the link works; the Roadmap page lists the meeting under backlinks; clicking it opens the meeting page ("Link from notes").
- [x] B5 Tag the notes `person/alex` on the meeting page → the meeting appears under `alex` in the tag tree (calendar icon) and under Meetings on the tag page of `person` ("Tagged meeting in the tree", "Person's meetings").
- [x] B6 ⌘K and search find the meeting by a word from its notes; Return opens its page ("Find a meeting by its notes").
- [x] B7 "…" → Delete Notes → the notes are in the Trash (calendar icon); Restore brings them back with sections and tags ("Delete and restore notes").
- [x] B8 Join on the meeting page opens the Teams link ("Join from the page").

## C. End to end (task 5.1)

- [x] C1 Write notes on a one-off test meeting, then delete that meeting in Calendar → the notes are still found by search; the page shows "No longer in the calendar" with the last known title and time ("Meeting deleted in the calendar").
- [x] C2 Ask Claude Code to prepare tomorrow's occurrence of the recurring meeting with a line linking `[[project/atlas/Roadmap]]` → it uses `update_meeting_notes`; the document gets a section for tomorrow on top; `get_schedule` for tomorrow shows `has_notes` ("Agent prepares a meeting").
