# Manual checks: quick-capture

Build and run: `scripts/build.sh && open build/Build/Products/Debug/gly.app`.
Neutral test data only (no real names). Setup: a tag `project/atlas` exists; a browser and another app open.

## A. Panel (task 2.1)

- [x] A1 With the browser in front, press ⌃⌥Space → the panel appears above it with the cursor in the field; pressing ⌃⌥Space again closes it ("Capture from another app").
- [x] A2 Type "Call venue tomorrow #project/atlas !" → the preview reads "Task · Call venue · due <tomorrow> · project/atlas · high"; Return → the panel closes, the browser stays in front, and the task exists with that due date, tag and priority ("Save and keep working").
- [x] A3 Open the panel, Tab to Page, type "Offsite ideas #project/atlas", ⌘Return → gly comes to the front with the new page open ("Save and open").
- [x] A4 Type something, Esc → nothing is created; click outside the panel → it closes, and reopening shows the typed text again ("Cancel").
- [x] A5 "Prepare friday retro" as a task → title stays "Prepare friday retro", no due date; "Retro fri" → due next Friday ("Words that only look like dates").
- [x] A6 Capture from a full-screen app (e.g. a full-screen browser window) → the panel shows on that space and typing works.
- [x] A7 ⌘Z in gly after a capture undoes the created task.

## B. Menu bar and settings (task 2.2)

- [x] B1 The menu bar shows the gly icon with Quick Capture (showing the shortcut), Open gly, Quit.
- [x] B2 Close the main window, press the shortcut and capture a task → reopen via the menu bar's Open gly → the task is there ("Window closed").
- [x] B3 Settings → Capture → record ⌃⇧T → ⌃⇧T opens the panel, ⌃⌥Space doesn't; Reset brings ⌃⌥Space back ("Change the shortcut").
- [x] B4 Turn off "Show in menu bar" → the icon disappears; on → it's back.
- [x] B5 Turn on "Open at login" → gly is listed in System Settings → General → Login Items; turn it off → removed.
