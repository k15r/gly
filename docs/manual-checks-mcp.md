# Manual checks: mcp-server

Build and run: `scripts/build.sh && open build/Build/Products/Debug/WorkDash.app`.
Registration (once): copy the command from WorkDash → Settings (⌘,) → Agents → Claude Code.
Use neutral test data only (no real names).

## A. Claude Code (task 4.3)

- [x] A1 `claude mcp list` shows `workdash` as connected.
- [ ] A2 In a **new** Claude Code session, ask for today's schedule: the reply lists today's SAP and iCloud appointments and today's due/overdue tasks.
- [ ] A3 Ask Claude Code to create a test task ("MCP test task", priority high, due tomorrow, tag `project/atlas`): it appears in the WorkDash task list at once.

## B. Settings → Agents (tasks 6.1, 6.2)

- [ ] B1 Status shows the store agent "running" and calendar access "fullAccess".
- [ ] B2 Switching "Local HTTP endpoint" on starts the listener (`lsof -nP -iTCP:47615 -sTCP:LISTEN` shows `127.0.0.1:47615`); switching it off stops it.
- [ ] B3 With the endpoint on, the copied URL works (`curl -s -X POST "<URL>" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'` lists the tools). After **Regenerate**, the old URL returns 401.
- [ ] B4 "Recent agent changes" lists the task created in A3 within a second, with client `claude-code`.

## C. End to end (task 7.1)

- [ ] C1 Hidden calendars (Sidebar → Calendars) don't appear in the schedule Claude Code reads.
- [ ] C2 Claude Code lists overdue tasks (it should use `list_tasks` with `due_before`).
- [ ] C3 Claude Code updates the test task: snooze until a date, change tags. Each change shows in the app at once and in "Recent agent changes".
- [x] C4 Claude Code deletes the test task: it disappears from the app. (Deleted tasks are only visible as "Delete …" in Recent agent changes; a trash bin with restore is a later change.)
- [ ] C5 Edit some task yourself, let Claude Code change another task, then press ⌘Z in WorkDash: only your edit is undone.
- [ ] C6 Developer → Unregister Agent, then ask Claude Code for the schedule: it gets an "agent unavailable" error quickly (no hang). Quit and reopen WorkDash to re-register.

## D. Joule experiment (task 7.2)

- [x] D1 Switch the HTTP endpoint on and copy the URL.
- [x] D2 In Joule → Add Connector, enter the URL (`http://127.0.0.1:47615/mcp/<token>`). Note whether the form accepts it. If not, try `http://localhost:47615/mcp/<token>`.
- [x] D3 Check what arrived: `/usr/bin/log show --last 10m --predicate 'process == "WorkDashAgent"' | grep http:`
  - nothing → Joule calls from the cloud; a local endpoint can't work
  - requests with a browser `origin=` and 403 → add that origin under "Allowed browser origins", Apply, retry
  - 200 responses → Joule can use WorkDash; try "what's on my schedule today?"
- [ ] D4 Record the outcome in the results table and switch the endpoint off again.

## Results

| Date | Checked by | Result | Notes |
|---|---|---|---|
| 2026-10-26 | owner | D ✅ | Joule works locally: the connector form accepted `http://127.0.0.1:47615/mcp/<token>`; requests come from the native **Joule Desktop** app (`User-Agent: Joule-Desktop/1.62.6`, no Origin), so no allow-list entry is needed. initialize/tools/list/tools/call → 200; one `GET` (SSE probe) → 405, which Joule tolerates. Joule listed all tools correctly. |
| | | | |
