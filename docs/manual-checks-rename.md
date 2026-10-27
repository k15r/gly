# Manual checks: rename-to-gly

Build and run: `scripts/build.sh && open build/Build/Products/Debug/gly.app`.
Setup: WorkDash quit and its agent stopped (`launchctl bootout gui/$(id -u)/dev.k15r.workdash.store-agent`, login item removed); gly not started before. Claude notes the WorkDash store's counts (tasks open/done, pages, meeting pages, tags) before the first start.

## A. Takeover (task 2.2)

- [x] A1 Start gly.app, allow its agent under Login Items if macOS asks → Dock, window title, menu bar item and its menu (Open gly, Quit gly) all say "gly" ("Name in the system").
- [x] A2 Tasks, pages, meeting pages and tags show the same counts Claude noted from WorkDash; the Trash holds what WorkDash's Trash held ("First start with WorkDash data").
- [x] A3 Open a page that links to a task → clicking the link opens that task; in edit mode the link reads `gly://item/…` ("Taken-over link").
- [x] A4 Paste a link copied from edit mode with its scheme changed to `workdash://` → it shows as a link and opens the same target ("Pasted old link").
- [x] A5 Settings → Planning shows the old working hours and effort sizes; hidden calendars stay hidden; Settings → Agents shows the HTTP endpoint with the old port and token.
- [x] A6 The agent asks for calendar access (new app) → allow → the day view shows appointments.
- [x] A7 Make a change in gly, quit gly and start it again → the change is there and nothing was copied again; Claude confirms the agent logged the takeover only once ("Later starts").
- [x] A8 Claude confirms the WorkDash database is unchanged (same counts, no new writes) ("WorkDash stopped before the switch").

## B. Switch-over (task 3.1)

- [x] B1 ⌃⌥Space opens quick capture (the shortcut is back to its default) and a captured task appears; the menu bar icon is shown.
- [x] B2 Edit a task, ⌘Z → the edit is undone.
- [x] B3 After Claude points `~/.claude.json` at gly and Claude Code is restarted, `claude mcp list` shows `gly` as connected and an agent can read the schedule through it.
- [x] B4 Optional: Settings → Capture → "Open at login" on → gly is listed under Login Items.
