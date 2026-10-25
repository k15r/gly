# Spikes

Throwaway code for the `foundation-spikes` change (`openspec/changes/foundation-spikes/`).

**Nothing in this directory may be reused in `WorkDashCore` or any product target.** Spikes exist to answer questions. Their results are recorded in `FINDINGS.md` files and in the change's `design.md`. Product code starts fresh.

| Directory | Spike | Question |
|---|---|---|
| `eventkit-probe/` | 1 | Is `calendarItemExternalIdentifier` + `occurrenceDate` a stable appointment key? |
| `store-spike/` | 2 | Does the GRDB/SQLite schema hold up (filters, FTS, reactivity, undo)? |
| `mcp-spike/` | 3 | Can a stdio MCP shim reach the app over XPC? |
