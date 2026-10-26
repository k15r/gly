# Design

## Context

The day-view change left this in place (see archive `2026-10-26-mac-day-view-and-tasks/design.md`):
- **`WorkDashAgent`** is a sandboxed launch agent inside `WorkDash.app` and the store's only writer. It vends the Mach service `DB33H6YGK7.dev.k15r.workdash.store-agent` with one XPC method, `perform(command, writer)`, which takes JSON `Command`s and checks the team code-signing requirement.
- **`WorkDashCore`** has the command handler, per-writer undo/redo, task and tag queries, `tasksForDay`, and an `EventKitSource`. EventKit is read only in the app process.
- **Calendar visibility, the device id** (used for writer names) and other preferences live in the app's standard `UserDefaults`.

The foundation spike (D5, Spike 3) proved the path Claude Code → stdio → unsandboxed `wd-mcp` → XPC → agent → SQLite with the official Swift MCP SDK (0.9 at the time).

Motivation and scope are in `proposal.md`. Behavior is in `specs/agent-access` and `specs/calendar-sources`.

## Goals / Non-Goals

**Goals:**
- **One MCP implementation, used by both transports.** It runs in the agent, next to the store and the calendar.
- **No new trust boundary beyond this Mac.** stdio relies on XPC code signing. HTTP relies on loopback, a token and an Origin check.
- **Find out cheaply whether Joule can use a local endpoint.**

**Non-Goals:**
- Remote exposure (tunnel, public HTTPS, OAuth).
- MCP sessions, SSE or server-initiated notifications.
- Resources and prompts.
- Per-agent permissions (every agent may do everything the tools offer).

## Decisions

### M1: The MCP server runs in the store agent, and `wd-mcp` is a message pipe

`wd-mcp` reads JSON-RPC messages line by line from stdin and forwards each one over XPC to the agent: a new method, `mcp(message, client, reply)`. It writes each reply to stdout. It holds no MCP logic. The only thing it remembers is the `clientInfo.name` from `initialize`, which it passes along with every message for attribution.

- **Why:**
  - **One implementation.** stdio and HTTP share the same tool code.
  - **EventKit stays in one process,** the agent, which has the calendar entitlement. A CLI tool started by Claude Code would get its calendar permission attributed to the terminal or Claude Code.
  - **The same place enforces store rules** for the app and for agents.
- **Alternative (spike shape):** `wd-mcp` runs the MCP server itself and calls commands over XPC. Rejected, because reads and calendar access would then need either a second XPC read API or database and EventKit access in the CLI.
- `wd-mcp` is an unsandboxed command-line tool, signed with the team and using the hardened runtime as in the spike. It's embedded at `WorkDash.app/Contents/MacOS/wd-mcp` and requires the agent's team signature on the XPC connection (same requirement as the app).

### M2: Stateless MCP handling in the agent

The agent treats every incoming JSON-RPC message on its own:
- `initialize` → server info and capabilities (tools only)
- `tools/list` → the tool list
- `tools/call` → the tool's result
- `ping` → empty result
- notifications → no reply

There is no session state, so stdio and HTTP use the same handler. The SDK is the official `modelcontextprotocol/swift-sdk` 0.11+.
- **Preferred:** the SDK's `Server` with `StatelessHTTPServerTransport`, fed one request at a time.
- **Fallback:** if that API can't process one message without an HTTP framework, use the SDK's message and tool types (`Tool`, `CallTool`, `Value`) with a small dispatcher of our own for the four methods.

Task 1.1 decides between the two in under an hour.

**Result (task 1.1): the SDK path, with SDK 0.12.1.** `StatelessHTTPServerTransport.handleRequest(HTTPRequest) -> HTTPResponse` is framework-agnostic, and `initialize`, `tools/list` and notifications work without a session (`SDKProbeTests`). The MCP library doesn't link SwiftNIO; only the SDK's conformance executables do.
- **One shared server.** The agent runs one `Server` + stateless transport. HTTP requests are passed through as they are. A stdio message from `wd-mcp` is wrapped as a `POST` `HTTPRequest`, with header `X-WorkDash-Client: <clientInfo.name>`, and marked as coming over XPC, so the Origin and token checks (M6) don't apply to it.
- **Writer from the request.** Tool handlers read `Server.currentHandlerContext?.httpContext` to find the writer: the `X-WorkDash-Client` header for stdio, otherwise `User-Agent` (M4).
- **Unique request ids.** The transport matches responses to waiting requests by JSON-RPC `id`. Two clients using the same id at the same time would collide. So the agent replaces each incoming request id with a unique one and restores the original in the response.

### M3: The tool layer lives in a new `WorkDashMCP` library target

`Packages/WorkDashCore` gets a second library target, `WorkDashMCP` (depends on `WorkDashCore` + MCP SDK). It contains the tool definitions with JSON input schemas, argument parsing and validation, and the mapping to existing `Command`s and queries. The output encoding is JSON text content, plus `structuredContent` where the SDK supports it. The app doesn't link the MCP SDK.
- **Reads** go directly to the agent's pool (`pool.read`).
- **Writes** go through `CommandHandler.perform(_:writer:)` in-process. The agent needs no XPC round trip to itself, and validation is the same as for the app.
- **Mapping:**
  - `create_task` → `createTask`
  - `update_task` → `updateTask` with the extended `TaskPatch` (tags, status, `snoozedUntil`; one batch, as introduced in E1)
  - `delete_task` → `deleteTask`
  - `get_task` → `TaskQueries.task`
  - `list_tags` → a new `TagQueries.list(prefix:)` with open counts
  - `get_schedule` → `tasksForDay` + appointments (M5)
- **`list_tasks`** uses a new `TaskQueries.find(TaskFilter)` with these filters:
  - status set
  - tag (same descendant `IN` subquery as the task list)
  - `due_before` / `due_after` on `due_day`
  - case-insensitive `title LIKE` with escaping
  - `limit + 1` to detect "more"

  It sorts in the task-list order (`openOrderSQL`) for open and snoozed tasks, and by most recent first for done and dropped.
- **Task JSON shape:**
  - `id`, `title`, `notes`, `status`, `priority`
  - `due: {day, time?}`, `snoozed_until`, `tags`
  - `created_at`, `modified_at`, `modified_by`

  Times are local ISO-8601 with offset. Dates are `YYYY-MM-DD`.
- **Errors:**
  - Validation, not-found and unavailable cases come back as tool results with `isError: true`, using the `CommandFailure` message as text. The model sees it and can correct itself.
  - Malformed JSON-RPC gets JSON-RPC errors.

### M4: Writer attribution

The writer is `agent:<client>@<device id>`, for example `agent:claude-code@mac-3f9a1c`.
- **`<client>`:**
  - stdio: the `clientInfo.name` from `initialize`, lowercased, with characters outside `[a-z0-9._-]` replaced by `-` and the length capped at 40.
  - HTTP is stateless, so later requests carry no `clientInfo`. There `<client>` is derived from the first `User-Agent` product token, and is `http` if there is none.
- **`<device id>`** moves from the app's standard defaults to the app-group defaults (M7), so the app and the agent use the same id.
- **Undo:** per-writer undo (L6) already guarantees the spec "User undo doesn't revert agent changes". Agents get no undo tool in this change.

### M5: The agent reads the calendar

The agent uses the existing `EventKitSource`. Changes:
- The agent gets the `com.apple.security.personal-information.calendars` entitlement and `NSCalendarsFullAccessUsageDescription` in its embedded Info.plist.
- It calls `requestFullAccessToEvents` on the first `get_schedule`.
- Visible calendars = all calendars minus the hidden IDs from the app-group defaults (M7).
- `get_schedule` builds its result with the same `DayModel` the app uses, so ordering, all-day separation and the cancelled flag match the day view.

**Risk:** this is the main unknown. It isn't clear how TCC treats a launch agent with its own Info.plist inside the app bundle: whether it prompts for the agent, attributes the request to `WorkDash.app`, or silently denies it. Task 1.2 checks this first.
- **Fallback, if the agent can't get access:**
  - While the app runs, it registers an anonymous XPC endpoint with the agent, and the agent asks the app for a day's appointments.
  - Without the app running, `get_schedule` returns tasks plus "appointments unavailable: open WorkDash", as the spec allows for missing access.
  - The fallback changes only M5's internals, not the tools.

**Result (task 1.2):** on the SAP Mac, the agent reports `fullAccess` (Developer → Check Agent Calendar Access). WorkDash.app already had full access, and the agent got it without a prompt: macOS applies the app's permission to the launch agent in its bundle. So the agent reads EventKit itself. The app fallback isn't built. `agentStatus` stays as a permanent read-only command for the Agents pane (M8).

### M6: Local HTTP listener (Network.framework)

- **Listener:** an `NWListener` in the agent, bound to `127.0.0.1` with loopback-only parameters, on port 47615 by default (configurable). It runs only while the setting is on. The agent gets `com.apple.security.network.server`.
- **Protocol:** a minimal HTTP/1.1 implementation.
  - It answers `POST` on the MCP path with `Content-Length` bodies, up to 1 MB.
  - `OPTIONS` handles CORS preflight for allowed origins.
  - Anything else gets `405`/`404`.
  - It sends `Connection: close` after each response, which keeps the parser trivial.
  - Responses are `application/json`; no SSE (stateless, M2).
- **Token:** 32 random bytes, base64url. It's accepted as a path segment (`/mcp/<token>`), for clients that only take a URL, such as the Joule connector form, or as `Authorization: Bearer <token>`. The comparison is constant-time. A wrong or missing token gets `401` with no body detail.
- **Origin:** a request without an `Origin` header (CLI clients) is allowed. With one, it must be in the user's allow list (empty by default), otherwise `403`. This protects against DNS rebinding and browser pages calling localhost. CORS headers are sent only for allowed origins.
- **Alternatives considered:**
  - Hummingbird or Vapor: robust HTTP, but SwiftNIO in a small agent for a single POST endpoint isn't worth it.
  - Embedding the token only in a header: the Joule form has a URL field only.
- **Joule experiment:** with the endpoint on, the user adds `http://127.0.0.1:47615/mcp/<token>` (or `localhost`) in Joule. The agent logs every rejected and accepted request: Origin, User-Agent, method, without the token. That shows what arrives:
  - If nothing arrives, Joule calls from the cloud, and local HTTP can't work. That's recorded in the findings; remote exposure would be a separate change.
  - If requests arrive from a browser origin, the user adds that origin to the allow list.

### M7: Shared settings in the app-group defaults

`UserDefaults(suiteName: "DB33H6YGK7.dev.k15r.workdash")` holds:
- `deviceID`
- `hiddenCalendarIDs`
- `httpEnabled`, `httpPort`, `httpToken`
- `httpAllowedOrigins`

On first launch the app copies `deviceID` and the hidden calendars from its standard defaults, if the group keys are missing. After a change, the app sends a new `Command.reloadSettings` over XPC. The agent re-reads the settings and starts, stops or rebinds the listener. A new command avoids polling and file watching.

The token is stored in the group defaults (readable only by team-signed group members) rather than the Keychain. That's acceptable for a loopback-only token and easy to regenerate. It's revisited if the endpoint ever becomes remote.

### M8: App "Agents" settings

A `Settings` scene (⌘,) with an "Agents" pane:
- **Status:** whether the agent is reachable, and the calendar access state the agent reports through a `Command.agentStatus` (new, read-only).
- **Claude Code:** the exact `claude mcp add --scope user workdash -- "<bundle path>/Contents/MacOS/wd-mcp"` command, with a Copy button. The path comes from `Bundle.main` at runtime, so it's correct wherever the app lives.
- **HTTP (experimental):**
  - On/off switch
  - Port
  - URL with the token, with a Copy button
  - Regenerate token
  - Allowed origins (one per line)
- **Recent agent changes:** the last 20 agent batches, from `change_log` with `writer LIKE 'agent:%'`, labeled with the existing `label(ofBatch:)`, with time and writer. It's observed live like the other lists.

## Risks / Trade-offs

- **[TCC denies or misattributes calendar access for the agent]** → Checked first (task 1.2). Fallback via the app (M5). `get_schedule` degrades to tasks only, with a clear message.
- **[Joule calls from SAP's cloud, so the local endpoint is unreachable]** → Expected as a likely outcome. The experiment costs little (M6 logging), and the result is recorded. A remote route (tunnel + OAuth) needs its own change and a policy check.
- **[Joule requires `https://`]** → Try `http://localhost` first. If the form rejects it, record that. A locally trusted certificate is a follow-up, not part of this change.
- **[Token leak gives full task access to local processes]** → Loopback only, off by default, regenerate in one click, Origin check against browsers. Every agent change is attributed and visible in "Recent agent changes".
- **[An agent makes many unwanted changes]** → All changes are soft and logged with the agent writer. A "revert agent batch" UI isn't in scope, but the change log has what it needs.
- **[MCP SDK API churn (0.9 → 0.11)]** → The tool layer depends only on message and tool types. The dispatcher fallback (M2) keeps the transport-facing part small.
- **[`wd-mcp` path changes when the app moves]** → The settings pane always shows the current path. A broken registration shows as "failed" in `claude mcp list`.
- **[Hand-written HTTP parser bugs]** → Narrow surface (POST, Content-Length, close after each response), size limit, unit tests with malformed requests.

## Migration Plan

- **Settings move to the app-group defaults** (M7) with a one-time copy. The old keys stay readable for one release, so a rollback to the previous build keeps working.
- **The spike's `workdash-spike` Claude Code registration** (if still present) is removed (`claude mcp remove workdash-spike`) and replaced by `workdash`.
- **No schema migration.** The store schema is unchanged; `change_log.writer` already holds free text.
