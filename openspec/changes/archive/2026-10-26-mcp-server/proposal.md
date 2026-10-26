# Proposal

## Why

WorkDash should be maintained by agents as well as by hand: an agent that reads mail or meeting notes should be able to see my day and create or update the resulting tasks directly in WorkDash. The foundation spike proved the path (Claude Code → MCP → XPC → launch agent → store) with a throwaway `get_schedule`. The day-view change now provides the real store, commands and calendar reading. This change exposes them as a production MCP server, so Claude Code (and, if it can reach the Mac, Joule) can read the schedule and fully manage tasks.

## What Changes

- **MCP server with these tools:**
  - `get_schedule`: appointments and tasks for a day (default today), same selection as the day view.
  - `list_tasks`: filter by status, tag (including descendants), due range, and text in the title.
  - `get_task`: one task with all fields.
  - `create_task`, `update_task`, `delete_task`: full CRUD, including status changes (complete, snooze, drop, reopen) and tags.
  - `list_tags`: existing tags with open-task counts, so agents reuse tags instead of inventing near-duplicates.
- **Two transports:**
  - **stdio** for Claude Code, through a small `wd-mcp` command inside the app bundle that talks XPC to the store agent. This is the route proven in the spike.
  - **Local HTTP** (Streamable HTTP, stateless) served by the store agent on `127.0.0.1` only, behind a secret token and an Origin check. It's an **experiment for Joule**: Joule's connector asks for a URL, and it is unclear whether Joule calls it from the local browser or from SAP's cloud. The endpoint is off by default and is switched on in the app.
- **Agent writes are attributed and separate from the user's undo:**
  - Every agent change is recorded with a writer `agent:<client>@<device>`.
  - ⌘Z in the app never reverts an agent's change.
  - Agent deletes are soft (recoverable).
- **The store agent reads the calendar itself** (EventKit) for `get_schedule`. It respects the calendar visibility chosen in the app, which moves to shared app-group settings.
- **App:** a small "Agents" settings pane with:
  - an MCP status line and the `claude mcp add` command to copy
  - the HTTP switch, URL and token (regenerate)
  - a list of recent agent changes

Not in this change: an inbox for underspecified tasks, info items, appointment annotations, public/remote exposure (tunnel, OAuth), a trash bin to see and restore deleted tasks (a later change; deletes stay recoverable in the store meanwhile), MCP resources/prompts, and notifications to agents about changes.

## Capabilities

### New Capabilities

- `agent-access`: how agents read and change WorkDash data over MCP. Covers the tools and their inputs and outputs, the transports and their protection, writer attribution, and the relation to user undo.

### Modified Capabilities

- `calendar-sources`: calendar visibility must also apply to agents reading the schedule (it's no longer just an app view setting).

## Impact

- **New code:**
  - `WorkDashCore`: MCP tool layer (tool definitions, input validation, mapping to existing `Command`s and queries), transport-independent so stdio and HTTP share it.
  - `WorkDashAgent`: EventKit reading, the MCP server for HTTP, and an XPC method for MCP requests from `wd-mcp`.
  - `wd-mcp`: a stdio command-line tool embedded in `WorkDash.app/Contents/MacOS` or `Contents/Helpers`.
- **Dependencies:** official MCP Swift SDK (`modelcontextprotocol/swift-sdk`, 0.11+) for the protocol and the stdio and stateless HTTP transports. Network.framework for the local listener.
- **Entitlements:**
  - the agent gets calendar access and the `network.server` sandbox entitlement (HTTP)
  - `wd-mcp` is unsandboxed or app-group sandboxed, as in the spike
- **System:** calendar permission may be asked once more for the agent. The HTTP port is reachable only from this Mac.
- **Security:**
  - The stdio route relies on XPC team code-signing checks.
  - The HTTP route relies on loopback binding, the token and Origin validation.
  - Anyone with the token and local access can read the schedule and change tasks.
