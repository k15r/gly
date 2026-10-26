# Tasks

## 1. Unknowns first

- [x] 1.1 Add `modelcontextprotocol/swift-sdk` 0.11+ to `Packages/WorkDashCore` as dependency of a new `WorkDashMCP` library target (design M3); write a throwaway test that feeds one `initialize` and one `tools/list` JSON-RPC message through the SDK's `Server` with the stateless transport without an HTTP framework; verify `swift build` succeeds, and record in `design.md` M2 whether the SDK path or the own-dispatcher fallback is used
- [x] 1.2 Give `WorkDashAgent` the calendar entitlement and `NSCalendarsFullAccessUsageDescription`, and add a temporary `Command.agentStatus` that requests EventKit access in the agent and reports the state; verify on the SAP Mac what happens (prompt for the agent, attributed to WorkDash, or silent denial) and record the result and the chosen M5 path (agent or app fallback) in `design.md`

## 2. Shared settings (app + agent)

- [x] 2.1 Add a `SharedSettings` type in `WorkDashCore` over the app-group `UserDefaults` (deviceID, hiddenCalendarIDs, httpEnabled, httpPort, httpToken, httpAllowedOrigins) with a one-time copy of `deviceID` and hidden calendars from the app's standard defaults (design M7); verify with tests using an isolated suite: defaults, migration copies only when group keys are missing, token generation is 32 random bytes base64url
- [x] 2.2 Switch the app's `AppModel.deviceID` and `CalendarModel.hiddenIDs` to `SharedSettings`, and add `Command.reloadSettings` (agent re-reads settings; no store change); verify the existing calendar visibility check B3 still passes after a rebuild, and a command test that `reloadSettings` returns ok without writing the change log

## 3. Tool layer (WorkDashMCP)

- [x] 3.1 Add `TaskQueries.find(TaskFilter)` (status set incl. `all`, tag with descendants, `due_before`/`due_after`, case-insensitive escaped title text, limit+1 for "more", sort per design M3) and `TagQueries.list(prefix:)` with open counts; verify with tests covering the `list_tasks` scenarios "Open tasks for a project", "Overdue tasks", "Truncated result" and the `list_tags` scenario
- [x] 3.2 Implement the tool definitions with JSON input schemas and descriptions (dates `YYYY-MM-DD`, times `HH:mm`, local) for `get_schedule`, `list_tasks`, `get_task`, `create_task`, `update_task`, `delete_task`, `list_tags`, and the task JSON encoding (design M3); verify with a test that `tools/list` returns all seven with schemas, and a snapshot test of one encoded task
- [x] 3.3 Implement the read tools (`list_tasks`, `get_task`, `list_tags`) on a database reader, with not-found as `isError` results; verify with tests for "Existing task", "Unknown or deleted task" and argument validation errors (bad date, unknown status)
- [x] 3.4 Implement the write tools (`create_task`, `update_task`, `delete_task`) through `CommandHandler` with writer `agent:<client>@<device>` (client name sanitized per design M4); verify with tests for "Task from an email", "Invalid input", "Complete a task", "Snooze needs a date", "Partial update" (one change-log batch), "Agent deletes a task" (tombstoned, history kept), and "Undo after an agent change" (user undo leaves the agent's batch)
- [x] 3.5 Implement `get_schedule` with an injected appointment provider (real: `EventKitSource` + hidden IDs from `SharedSettings`; tests: `FakeEventSource`), reusing `DayModel` and `tasksForDay`; verify with tests for "Today's schedule", "Another day", "No calendar access" (tasks still returned, appointments reported unavailable) and "Hidden calendar and agents"
- [x] 3.6 Implement the stateless message handler (initialize, tools/list, tools/call, ping, notifications → no reply; malformed JSON-RPC → JSON-RPC error) per design M2; verify with tests feeding raw JSON-RPC messages and checking replies

## 4. stdio route (agent + wd-mcp)

- [x] 4.1 Add the XPC method `mcp(message, client, reply)` to the agent protocol, served by the message handler from 3.6 with the agent's pool and calendar source; verify with an anonymous-listener XPC test (like `AgentXPCTests`) that `tools/call create_task` creates a task attributed to `agent:test@…`
- [x] 4.2 Add the `wd-mcp` command-line target to `project.yml` (unsandboxed, hardened runtime, team signed, embedded at `Contents/MacOS/wd-mcp`): reads JSON-RPC lines from stdin, remembers `clientInfo.name`, forwards over XPC with the team code requirement, writes replies to stdout, returns a JSON-RPC error "WorkDash agent unavailable" within 5 s when XPC fails; verify `scripts/build.sh` includes and signs it, and a piped `initialize` + `tools/list` from the shell returns the seven tools
- [ ] 4.3 Register in Claude Code with `claude mcp add --scope user workdash -- <bundle>/Contents/MacOS/wd-mcp` (remove `workdash-spike` if present); verify `claude mcp list` shows `workdash` connected, and in a new Claude Code session `get_schedule` returns today's appointments and tasks and `create_task` makes a task that appears in the app without refresh

## 5. Local HTTP route (agent)

- [x] 5.1 Implement the minimal HTTP/1.1 request parser and response writer (POST with Content-Length ≤ 1 MB, OPTIONS, 404/405/413/400, `Connection: close`) as a pure type in `WorkDashMCP`; verify with unit tests including malformed request lines, missing/oversized Content-Length and split reads
- [x] 5.2 Implement token check (path `/mcp/<token>` or `Authorization: Bearer`, constant-time compare → 401) and Origin policy (no Origin ok; Origin must be in the allow list → else 403; CORS headers and preflight only for allowed origins) per design M6; verify with unit tests for "Wrong token", allowed/blocked Origin and preflight
- [x] 5.3 Run an `NWListener` on `127.0.0.1:<port>` in the agent, started/stopped/rebound on `reloadSettings`, with the `network.server` entitlement, logging each request's method, path without token, Origin and User-Agent; verify: with HTTP off `lsof -iTCP:47615` shows nothing ("Endpoint off"); with it on, `curl` to the URL with token lists the tools ("Valid request"), without token gets 401, and a connection to the Mac's LAN address is refused ("Other machine")
- [x] 5.4 Derive the HTTP writer `agent:<user-agent token>@<device>` (fallback `http`); verify with a test that a `create_task` over HTTP with `User-Agent: joule/1.0` is recorded as `agent:joule@…`

## 6. App: Agents settings

- [ ] 6.1 Add the Settings scene (⌘,) with the "Agents" pane: agent reachability and calendar state (`agentStatus`), the `claude mcp add` command with the current bundle path and a Copy button, HTTP switch, port, URL with token and Copy, Regenerate token, allowed origins; changes write `SharedSettings` and send `reloadSettings`; verify manually that toggling HTTP starts/stops the listener (5.3 check) and regenerating the token makes the old URL return 401
- [ ] 6.2 Add "Recent agent changes" (last 20 agent batches from `change_log`, labeled via `label(ofBatch:)`, with time and writer, live-updating); verify with a query test and manually that a task created from Claude Code appears in the list within a second

## 7. End to end

- [ ] 7.1 Manual checks, documented in `docs/manual-checks-mcp.md`: Claude Code reads today's schedule (SAP + iCloud, hidden calendars excluded), lists overdue tasks, creates, updates (snooze, tags) and deletes a task; each change shows in the app at once and in "Recent agent changes"; ⌘Z in the app doesn't revert the agent's change; agent stopped → tool calls fail fast with the "unavailable" message
- [ ] 7.2 Joule experiment: switch HTTP on, add the URL as a Joule connector, try `http://127.0.0.1…` and `http://localhost…`; record in `docs/manual-checks-mcp.md` what the form accepts and what the agent log shows (no request / browser Origin / tool calls) and the conclusion for a follow-up change

## Workflow follow-up

- Run `/opsx:verify mcp-server`, then archive the change once the manual checks pass.
- Depending on the Joule result: propose a change for remote access (tunnel + OAuth, after a policy check) or drop the HTTP route.
