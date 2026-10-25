# Spike 1 findings: appointment identity

Probe: `eventkit-probe` (this directory). Mac: macOS 27.0.1, Xcode 27.1.

## Setup notes

- Calendar access for a CLI tool is requested on behalf of the **hosting terminal app** (here iTerm2). The first request needs a human to click "Allow". The MDM TCC profile on the SAP Mac does not block calendar access.
- `requestFullAccessToEvents` needs a running main run loop. Blocking the main thread with a semaphore hangs forever.

## Calendars available (2026-10-25)

- iCloud (personal + shared family calendars), subscribed (holidays), birthdays.
- **SAP Exchange** added on 2026-10-25. The account first appeared in EventKit as a source with **0 calendars** (mail already worked). The calendars (`Kalender`, `Geburtstage`, `Feiertage in Deutschland`) appeared minutes later without any action. The initial sync then fills events in gradually (10 → 36 events in the same 60-day window within minutes).

## Results

### F1: `externalId + occurrenceDate` is NOT unique; the calendar must be part of the key (iCloud, verified)

In a 60-day window, 9 occurrences of one series existed **in two calendars at once** (two shared family iCloud calendars, "Shared calendar A" and "Shared calendar B"), with identical `calendarItemExternalIdentifier`, `occurrenceDate`, title and start.

→ The key must include the calendar: `calendar + externalId + occurrenceDate`.

Open: which calendar identifier is stable across devices? `calendarIdentifier` is documented as potentially changing on sync. The probe currently uses `source.title/calendar.title`, which breaks on calendar rename. To be decided (candidates: title-based with rename handling, or snapshot fuzzy match as fallback).

### F2: Snapshot/diff is stable (verified)

Two snapshots 2 s apart (131 events, 60 days) diff to **0 differences** with the calendar-qualified key.

### F3: Series behaviour on iCloud (partially verified, task 2.7)

- 24 recurring series (per calendar) in the window. Within each series, every occurrence has a distinct `occurrenceDate` and the same `calendarItemExternalIdentifier`.
- For non-detached occurrences `occurrenceDate == startDate`.
- `eventIdentifier` is **shared by all occurrences of a series** (and is device-local per docs), so it can't be used as an occurrence key.
- External IDs of Google-originated events look like `…@google.com`. iCloud passes them through.
- Pending: moved occurrence, title change, attendee change (needs a self-created test series, see task 2.4).

### F4: SAP Exchange series share the external ID; occurrences are distinct (verified, task 2.3)

- 10 recurring SAP series in the window (incl. several weekly 1:1s and team sprint meetings). Within each series all occurrences share `calendarItemExternalIdentifier` and have distinct `occurrenceDate`.
- SAP external IDs are 36-character UUID-style strings (e.g. `DC31E036-B548-…`), not the long hex Graph `iCalUId` format. **If an agent path is ever used in parallel, the IDs from Graph and from EventKit probably won't match directly.** Matching would need the snapshot fuzzy match or a mapping.
- Every SAP event has an organizer, which is useful for the fuzzy fallback key.
- During initial sync, snapshot diffs show **only additions**, so no key changed while syncing.

### F5: Organizer-cancelled series (partially verified, task 2.6)

- A series cancelled by its organizer (a weekly cross-team call) appears with **both** `status == .canceled` **and** the title prefix `Canceled: `, and it stays visible in EventKit.
- So `status == .canceled` is the primary rule, and the title prefix is a fallback. Pending: a self-cancelled meeting, and a single cancelled occurrence (does it disappear or stay with status canceled?).

### F6: Editing a single occurrence detaches it and changes its external ID (iCloud, verified, task 2.7)

Test series `WD-Test iCloud` (4 weekly occurrences, self-organized).

- **Moving** occurrence 2 by +1 h ("only this event"): external ID became `<base>/RID=815299200`, `isDetached = true`, `hasRecurrence = false`, and **`occurrenceDate` followed the new start (09:00)**. That contradicts the documented "original occurrence date" semantics.
- **Renaming** occurrence 3 ("only this event"): same pattern, `/RID=…` suffix added, start unchanged.
- The `RID` value is the **original start in seconds since 2001-01-01** (`815299200` → 2026-11-02 08:00 UTC).
- **Normalized key** `calendar + base ID (RID stripped) + original start (from RID, else occurrenceDate)`: after move + rename, all 4 normalized keys **equal the baseline keys** (verified). The probe now computes `stableKey` and diffs on it.

### F7: "All future events" splits the series into a new ID (iCloud, verified, task 2.5)

Moving occurrence 3 by +30 min with "all future events":

- The old series (`14B43DC8…`) is **truncated** to occurrences 1 and 2.
- A **new series** (`4B3D582F…`) holds occurrences 3 (still detached, keeps its RID) and 4.
- Occurrence 4's original start changes too (08:00 → 08:30), because the new series starts at the new time.
- → Exact matching **fails** for all occurrences after the split point. Annotations need the **fuzzy fallback**: same calendar, same day, similar title, old series ending where the new one begins.
- → **Series tag rules** must follow splits. Proposal: when a series ends and a series with the same title (+ organizer for Exchange) starts at the next slot, carry the rule over (ask the user if not certain).

### F8: Deleting one occurrence can change the key of ANOTHER occurrence (iCloud, verified)

Deleting occurrence 4 ("only this event") left the split series `4B3D582F…` with a single occurrence. Calendar converted it into a **plain single event** (`hasRecurrence = false`, `isDetached = false`, `/RID=…` removed). Its normalized key jumped from `…@08:00` (original start) to `…@08:30`, although occurrence 3 itself was not edited.

→ Keys can change through edits to *other* occurrences. WorkDash needs **key migration**: on `EKEventStoreChanged`, every annotated appointment whose key no longer resolves is re-matched fuzzily. A clear match **updates the stored key**. Only no match → `gone`. Fuzzy matching is a normal path, not an edge case.

### F9: Deleting own iCloud events = disappearance (iCloud, verified, task 2.6)

- Deleting a single occurrence and deleting whole series: the events **vanish** from EventKit. There's no `canceled` status.
- Together with F5 (organizer-cancelled SAP series stays visible with `status == .canceled` + `Canceled:` prefix):
  - **`cancelled`** = `status == .canceled` (title prefix `Canceled:` as fallback)
  - **`gone`** = annotated key no longer resolves **and** no fuzzy match found

### F10: Exchange shows the same detach/RID pattern (SAP, verified, task 2.4)

Test series `WD-Test SAP` (4 weekly occurrences, organized in Outlook, 2 attendees). Moving occurrence 2 by +1 h ("this occurrence") in Outlook:

- External ID became `1A0F46B0-…/RID=815315400`, `isDetached = true`, `hasRecurrence = false`, `occurrenceDate` = new start (13:30 UTC).
- `RID=815315400` decodes to 2026-11-02 12:30 UTC, the **original** start. So the normalized key from F6 works for Exchange too.
- **Rename + attendee removal** of occurrence 3 (single occurrence): ID became `…/RID=815920200` (= 2026-11-09 12:30 UTC, original start), title changed, attendees 2 → 0.
- After move + rename + attendee change, **all 4 normalized keys equal the original slots** (same base ID, original 12:30 starts). Verified.
- Sync latency Outlook → Apple Calendar was **20+ minutes** for both creation and the move on 2026-10-25 (across a reboot). The later rename + attendee change arrived within a few minutes.

## Pending

- Optional: attendee change on the whole SAP series (only a single-occurrence attendee change was observed).
- Optional: "this and all following" split on SAP (F7 verified on iCloud).
- Optional: attendee view of cancellations (needs an invitation received from someone else).
