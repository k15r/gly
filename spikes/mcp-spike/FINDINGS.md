# Spike 3 findings: MCP process model

Project: `spikes/mcp-spike` (XcodeGen `project.yml` → `xcodebuild`), signed with an Apple Development certificate (free personal team `DB33H6YGK7`) on the SAP-managed Mac. MCP via the official Swift SDK (`modelcontextprotocol/swift-sdk` 0.9.x).

## Architecture tested (option Y, refined)

```
Claude Code --stdio--> wd-mcp (shim, not sandboxed, stateless)
                          |  NSXPCConnection(machServiceName: "DB33H6YGK7.dev.k15r.workdash.spike-agent")
                          v
                       WorkDashAgent (launch agent in the app bundle, sandboxed)
                          owns the SQLite store in the app group container
WorkDashSpike.app (UI, sandboxed) registers the agent via SMAppService.agent(plistName:)
```

## M1: A GUI app can't vend the Mach service; a launch agent in the bundle can

- The fixed XPC endpoint for an outside process has to be a **launch agent** (`Contents/Library/LaunchAgents/*.plist` with `BundleProgram` + `MachServices`), registered by the app through `SMAppService.agent`.
- A **sandboxed** agent may register a Mach name only if it's prefixed with its **app group** (`DB33H6YGK7.dev.k15r.workdash.*`). That works with the free team, without a provisioning profile (verified).
- → The "single writer" of D5 option Y is the **agent**, not the window app. The window app becomes a client too.

## M2: Signing and sandbox work on the managed Mac (task 1.2, 4.1)

- The app, agent and shim are all signed with team `DB33H6YGK7`, hardened runtime, and `codesign --verify --deep --strict` passes. The app + agent are sandboxed with the app group.
- No MDM/Gatekeeper blocks for locally built, development-signed apps.

## M3: XPC round trip and on-demand launch (tasks 4.1, 4.4)

| Case | Result |
|---|---|
| Shim `--ping` / `--schedule` → agent | Works |
| UI app closed + agent process killed → shim call | launchd starts the agent **on demand**, answers in **~100 ms** |
| Agent unloaded from launchd (`launchctl bootout`) | Clear MCP error after **~60 ms**: "WorkDash agent not reachable … enable it in Login Items" |

- Both sides check the peer's code signature (`setCodeSigningRequirement` for team `DB33H6YGK7`). Only our own signed processes can connect.
- The UI app does **not** need to run for MCP. The agent is the always-available backend (login item).

## M4: MCP over stdio with the Swift SDK (tasks 4.2, 4.3)

- Raw JSON-RPC over stdin: `initialize` (protocol `2025-06-18`), `tools/list` → `["get_schedule"]`, `tools/call get_schedule` → JSON payload. All work.
- `claude mcp add --scope local workdash-spike -- <path to wd-mcp>` → `claude mcp get` reports **Connected**.
- Pitfall: in the shim's top-level async code, blocking the main thread with a semaphore deadlocks the `Task`, so the timeout never fires. Use `await` directly.
- **SDK choice: official Swift MCP SDK.** It was straightforward (`withMethodHandler(ListTools/CallTool)`, `StdioTransport`). No reason to hand-write JSON-RPC.

## M5: Real data from the store (task 4.5)

- The agent opens the Spike 2 store (`StoreSpike` as a local package) in the **app group container** (`~/Library/Group Containers/DB33H6YGK7.dev.k15r.workdash/`) and answers `get_schedule` with local appointments + open tasks due that day, including tags.
- Verified over raw MCP: `source: store`, 9,710 live items, 3 events + 8 tasks for today.
- The first call generated the fixture (several seconds). Normal calls are fast.

## M6: Live call from Claude Code (tasks 4.3, 4.5)

- In a new Claude Code session, the `workdash-spike` server's `get_schedule` returned today's store data (3 events, 8 open tasks with tags, 9,710 items). The whole path works: Claude Code → stdio shim → XPC → launch agent → SQLite.
- The agent on the other side noticed two things worth keeping:
  - **Times were UTC only.** The agent had to convert to local time itself (and today was the DST switch in Germany). → **MCP payloads must carry local time with offset plus the time zone ID** (e.g. `2026-10-25T20:40:00+01:00`, `Europe/Berlin`), not bare UTC.
  - The generator gives every item the same time of day (whole-day offsets from "now"). That's a test data artifact only.
