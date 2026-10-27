# Manual checks: meeting-note-icon

Build and run: `scripts/build.sh && open build/Build/Products/Debug/gly.app` (quit gly first so the new build runs).
Neutral test data only (no real names). Setup: today has an appointment with notes (write a line on its meeting page if needed) and one without; a recurring meeting with notes from an earlier occurrence.

## A. Day view (task 1.1)

- [ ] A1 Hover the notes icon next to an appointment with notes → tooltip "Open notes"; click it → the meeting page opens with the notes, and no details popover appears ("Open notes from the day view").
- [ ] A2 Click the title of the same appointment → its details popover opens as before ("Click on the rest of the appointment").
- [ ] A3 On a recurring meeting's occurrence, click the notes icon → the series notes open at that day's section.
- [ ] A4 An appointment without notes shows no icon.
