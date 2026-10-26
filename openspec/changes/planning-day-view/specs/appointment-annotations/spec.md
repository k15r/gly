# Spec Delta

## Purpose

Lets the user attach their own information to calendar appointments they can't edit, starting with whether an appointment really blocks their time, so that the information follows the appointment through moves and series changes and survives when it disappears.

## ADDED Requirements

### Requirement: Blocking override menu
Each appointment in the day view SHALL offer a small menu to set how it counts for free time: blocks, optional (counts half) or ignore, or back to automatic. The choice SHALL apply either to this occurrence or to the whole series (for recurring appointments). The current choice SHALL be visible on the appointment row.

#### Scenario: Skip one meeting
- **WHEN** the user chooses "Ignore – this occurrence" on an accepted weekly sync
- **THEN** that occurrence no longer reduces free time, the row shows that it is ignored, and the next occurrence still blocks

#### Scenario: Optional series
- **WHEN** the user chooses "Optional – whole series" on a weekly info session
- **THEN** every occurrence of that series counts half

#### Scenario: Back to automatic
- **WHEN** the user chooses "Automatic" on an occurrence with an override
- **THEN** the occurrence is classified from the calendar again

### Requirement: Occurrence overrides win over series overrides
For an occurrence with both an occurrence override and a series override, the occurrence override SHALL apply.

#### Scenario: Exception in an optional series
- **WHEN** a series is optional and the user sets one occurrence to blocks
- **THEN** that occurrence blocks and the others count half

### Requirement: Annotations follow their appointment
An annotation SHALL stay attached to its appointment when the appointment is moved, renamed or gets new attendees, when only some occurrences of a series are edited, and when the calendar identifies the appointment differently after a change. When the system cannot decide between several possible appointments, it SHALL ask the user.

#### Scenario: Meeting moved
- **WHEN** an occurrence with an override is moved from 10:00 to 14:00 in Outlook
- **THEN** the override applies at 14:00

#### Scenario: Ambiguous match
- **WHEN** after a calendar change two appointments on the same day match an annotation equally well
- **THEN** the day view asks the user which one it belongs to, and the override is not applied until answered

### Requirement: Series overrides follow series splits
A series override SHALL also apply to the continuation of a series that was split by an "all future events" change (same title and organizer, continuing at the next regular time).

#### Scenario: Series split
- **WHEN** the organizer moves "all future events" of an optional series to a new weekday
- **THEN** the new occurrences are optional too

### Requirement: Annotation life cycle
An annotated appointment SHALL be active while it exists in the calendar, cancelled when the calendar reports it cancelled, and gone when it can no longer be found. Annotations SHALL never be deleted automatically, and SHALL keep a snapshot of title, start, end and calendar. Appointments without annotations SHALL NOT be stored.

#### Scenario: Annotated meeting deleted
- **WHEN** an occurrence with an override is deleted from the calendar
- **THEN** its annotation becomes gone, it no longer affects free time, and it is kept with its snapshot
