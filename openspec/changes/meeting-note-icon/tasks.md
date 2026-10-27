# Tasks

## 1. Day view

- [x] 1.1 Make the notes icon in `AppointmentRow` a borderless button that opens the meeting page (`nav.go(.meeting(.appointment(a)))`, the same target as the popover's Notes button), with the tooltip "Open notes", taking the click before the row's tap gesture; verify with a clean build and manually "Open notes from the day view" and "Click on the rest of the appointment"

## 2. End to end

- [x] 2.1 Write `docs/manual-checks-meeting-note-icon.md` (neutral test data) and push it as gly tasks with `scripts/manual-checks.py push`; covers the two scenarios plus a recurring meeting's notes opening at that day's section and an appointment without notes showing no icon; done when `pull` reports every check passed

## Workflow follow-up

- Run `/opsx:verify meeting-note-icon`, then archive after the manual checks pass.
