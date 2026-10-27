# Spec Delta

## Purpose

Gives every meeting a place for notes: one ever-growing document per recurring series, one per one-off meeting, reachable from the day view and connected to pages, tasks and tags through links and tags.

## ADDED Requirements

### Requirement: Notes document per meeting
A recurring meeting SHALL have one notes document for its whole series, and a one-off meeting one document of its own. The series document SHALL stay with the series when it is renamed or split, the same way series overrides do. A document SHALL be created only when text is first written to it.

#### Scenario: Weekly 1:1
- **WHEN** the user writes notes in two different weeks of the weekly "1:1 Alex"
- **THEN** both are in the same document, and opening any occurrence of the series shows it

#### Scenario: Series split
- **WHEN** the organizer changes the series from next week on, which splits it in the calendar
- **THEN** opening a meeting after the split still shows the same notes document

#### Scenario: Nothing written
- **WHEN** the user opens the meeting page of a meeting and writes nothing
- **THEN** no notes document is stored for it

### Requirement: Dated sections in series notes
A series document SHALL be organized in sections headed by the meeting date (for example `## Tue 3 Nov`), newest on top. Opening the meeting page from a specific occurrence SHALL place the cursor in that occurrence's section; its heading SHALL be added only when text is written there.

#### Scenario: Write today's notes
- **WHEN** the series document has a section for 27 Oct and the user opens the 3 Nov occurrence and types "agreed on scope"
- **THEN** the document starts with `## Tue 3 Nov` and "agreed on scope", followed by the 27 Oct section

#### Scenario: Open an earlier meeting
- **WHEN** the user opens the 27 Oct occurrence of the series
- **THEN** the page shows the series document scrolled to the 27 Oct section

### Requirement: Meeting page
The meeting page SHALL show the meeting's title, time, calendar, location, organizer and attendees, its description with clickable links and a folded dial-in block, and a join button when the description or location contains a meeting link, followed by the notes document with tags and backlinks. Notes SHALL be edited like page text (links, autosave, one undo step per edit session).

#### Scenario: Join from the page
- **WHEN** the user opens the page of a Teams meeting
- **THEN** a Join button opens the Teams link

#### Scenario: Link from notes
- **WHEN** the notes contain `[[project/atlas/Roadmap]]`
- **THEN** the link works, and the Roadmap page lists the meeting under its backlinks

### Requirement: Meeting notes outlive the meeting
Notes SHALL never be deleted when a meeting changes in the calendar. If a meeting is cancelled or no longer found, its page SHALL still open from search, tags and backlinks, show the last known title and time, and mark the meeting as cancelled or no longer in the calendar. The description SHALL be read from the calendar when shown and SHALL NOT be stored.

#### Scenario: Meeting deleted in the calendar
- **WHEN** a one-off meeting with notes is deleted in the calendar
- **THEN** its notes are still found by search, and the page shows "no longer in the calendar" with the last known title and time

### Requirement: Delete meeting notes
The user SHALL be able to delete a meeting's notes document; it SHALL go to the Trash and be restorable like pages and tasks. Blocking overrides of the meeting SHALL stay.

#### Scenario: Delete and restore notes
- **WHEN** the user deletes the notes of "1:1 Alex" and restores them from the Trash
- **THEN** the document is back with all sections, tags and links
