# Proposal

## Why

Meetings produce action items, and in gly they end up as checklist lines in the meeting notes (`- [ ] send agenda`). There they stay: they don't show up in the plan, have no due date or effort, and before the next meeting of the series nothing reminds me which of them are still open.

## What Changes

- **Make task from an action item:** on a meeting page, each open checklist item of the notes offers "Make task". The item becomes a task: its text is the title, it gets the meeting's tags, and its notes link back to the meeting. In the meeting notes, the line becomes a link to the new task. Both happen in one step, which one undo reverts.
- **Open action items:** a meeting page lists the still-open tasks made from its notes. For a series, that includes earlier meetings, so the next 1:1 shows what's left from the last one.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `meeting-pages`: adds turning action items into tasks and the list of open action items.

## Impact

- `GlyCore`: a command that creates the task and rewrites the notes line in one batch; the open action items via the link index (tasks whose notes link to the meeting notes).
- App: an "Action items" panel on the meeting page (open checklist items with "Make task"; open tasks made from these notes).
- No MCP changes. Agents can already create tasks and edit notes.
