# Spec Delta

## Purpose

Lets AI agents (MCP clients such as Claude Code) read the day's schedule and tasks and create, change and delete tasks in WorkDash, with every agent change attributed and kept separate from the user's own undo.

## ADDED Requirements

### Requirement: Read the schedule of a day
The system SHALL provide an MCP tool `get_schedule` that returns, for a given date (default: today, local time), the appointments of all visible calendars and the tasks the day view shows for that date. Each appointment SHALL include title, start, end, all-day flag, cancelled flag, calendar name, location, organizer and attendees.

#### Scenario: Today's schedule
- **WHEN** an agent calls `get_schedule` without arguments
- **THEN** it receives today's appointments in start order and today's due and overdue open tasks, matching the day view

#### Scenario: Another day
- **WHEN** an agent calls `get_schedule` with `date: "2026-10-28"`
- **THEN** it receives the appointments and tasks due on 28 October, without overdue tasks

#### Scenario: No calendar access
- **WHEN** the agent process has no calendar access
- **THEN** `get_schedule` still returns the tasks, and reports that appointments are unavailable because calendar access is missing

### Requirement: List tasks
The system SHALL provide an MCP tool `list_tasks` that returns tasks filtered by any combination of: status (`open`, `snoozed`, `done`, `dropped`, or `all`; default `open`, which includes snoozed tasks), tag (including descendants), due on or before / on or after a date, and text contained in the title (case-insensitive). Results SHALL be sorted like the task list and limited to a maximum count (default 50), and SHALL say when more results exist.

#### Scenario: Open tasks for a project
- **WHEN** an agent calls `list_tasks` with `tag: "project/atlas"`
- **THEN** it receives the open and snoozed tasks tagged `project/atlas` or below, sorted by priority and due date

#### Scenario: Overdue tasks
- **WHEN** an agent calls `list_tasks` with `due_before: <yesterday>`
- **THEN** it receives only open tasks with a due date up to yesterday

#### Scenario: Truncated result
- **WHEN** 80 tasks match and no limit is given
- **THEN** 50 tasks are returned and the response states that more exist

### Requirement: Read one task
The system SHALL provide an MCP tool `get_task` that returns one task by id with all its fields: id, title, notes, status, priority, due date and optional time, snooze date, tags, created and modified time, and who last modified it.

#### Scenario: Existing task
- **WHEN** an agent calls `get_task` with the id of an existing task
- **THEN** it receives all fields of that task

#### Scenario: Unknown or deleted task
- **WHEN** an agent calls `get_task` with an id that doesn't exist or was deleted
- **THEN** it receives a "not found" error

### Requirement: Create a task
The system SHALL provide an MCP tool `create_task` that creates a task with a required title and optional notes, priority, due date (with optional time), tags and status. The same validation as in the app SHALL apply. The response SHALL contain the new task's id and fields.

#### Scenario: Task from an email
- **WHEN** an agent calls `create_task` with title "Send load-test report", priority `high`, due `2026-10-29` and tags `["project/atlas"]`
- **THEN** the task exists in WorkDash with these values and appears in the app without refresh

#### Scenario: Invalid input
- **WHEN** an agent calls `create_task` with an empty title or the tag `project//x`
- **THEN** no task is created and the error message says what is wrong

### Requirement: Update a task
The system SHALL provide an MCP tool `update_task` that changes only the given fields of a task: title, notes, priority, due date (or clearing it), tags (replacing the set), and status including snooze with a snooze date. All changes of one call SHALL be one change in the history.

#### Scenario: Complete a task
- **WHEN** an agent calls `update_task` with `status: "done"`
- **THEN** the task is done and disappears from the open views in the app

#### Scenario: Snooze needs a date
- **WHEN** an agent calls `update_task` with `status: "snoozed"` and no snooze date
- **THEN** the task is unchanged and the error says a snooze date is required

#### Scenario: Partial update
- **WHEN** an agent calls `update_task` with only a new priority
- **THEN** only the priority changes; title, notes, due date and tags stay as they were

### Requirement: Delete a task
The system SHALL provide an MCP tool `delete_task` that deletes a task by id. The deletion SHALL be recoverable: the task's data and history SHALL be kept.

#### Scenario: Agent deletes a task
- **WHEN** an agent calls `delete_task` for an existing task
- **THEN** the task disappears from all views, and its data remains in the store's history

### Requirement: List tags
The system SHALL provide an MCP tool `list_tags` that returns existing tags with their number of open tasks, optionally filtered by a prefix, so agents can reuse existing tags.

#### Scenario: Tags below a prefix
- **WHEN** tags `person/alex` and `person/sam` exist and an agent calls `list_tags` with `prefix: "person/"`
- **THEN** both tags are returned with their open-task counts

### Requirement: Tool descriptions guide agents
Every tool SHALL describe its purpose, its inputs with types and allowed values, and its output, in the tool list the MCP server provides. Dates SHALL be `YYYY-MM-DD` and times `HH:mm` in local time, and the descriptions SHALL say so.

#### Scenario: Agent discovers the tools
- **WHEN** an MCP client lists the tools
- **THEN** it receives `get_schedule`, `list_tasks`, `get_task`, `create_task`, `update_task`, `delete_task` and `list_tags`, each with an input schema and description

### Requirement: Agent changes are attributed
Every change made through MCP SHALL be recorded in the history with a writer that identifies it as an agent change, including the client name the MCP client reports, for example `agent:claude-code@<device>`. The app SHALL show recent agent changes.

#### Scenario: History shows the agent
- **WHEN** Claude Code creates a task via MCP
- **THEN** the history records the creation with writer `agent:claude-code@<device>`, and the app's recent agent changes list it

### Requirement: User undo doesn't revert agent changes
Undo and redo in the app SHALL only affect changes made by the user in the app. A change made by an agent SHALL never be reverted by the user's Undo command.

#### Scenario: Undo after an agent change
- **WHEN** the user edits task A, then an agent edits task B, then the user chooses Undo
- **THEN** the user's edit of task A is reverted and the agent's edit of task B stays

### Requirement: Local command-line access for MCP clients
The system SHALL provide a command that MCP clients can start to talk MCP over standard input and output, and the app SHALL show the exact command to register it with Claude Code. The command SHALL only work while the WorkDash store agent is available and SHALL report a clear error otherwise.

#### Scenario: Register in Claude Code
- **WHEN** the user runs the registration command shown in the app
- **THEN** Claude Code reports the WorkDash MCP server as connected and can call its tools

#### Scenario: Store agent not available
- **WHEN** the store agent isn't running or not approved
- **THEN** tool calls return an error saying WorkDash's agent is unavailable, instead of hanging

### Requirement: Local HTTP access
The system SHALL offer an MCP endpoint over HTTP that is off by default and switched on by the user in the app. When on, it SHALL accept connections only from this Mac, and SHALL require a secret token that the app shows together with the URL and can regenerate. Requests without the valid token, or with a browser Origin that isn't allowed, SHALL be rejected without revealing data.

#### Scenario: Endpoint off
- **WHEN** the user hasn't switched on HTTP access
- **THEN** no port is listening for MCP

#### Scenario: Valid request
- **WHEN** HTTP access is on and a client on this Mac calls the URL shown in the app (which contains the token)
- **THEN** it can list and call the tools

#### Scenario: Wrong token
- **WHEN** a request uses a missing or outdated token
- **THEN** it is rejected with an authorization error and no data

#### Scenario: Other machine
- **WHEN** another computer on the network tries to connect to the port
- **THEN** the connection is refused
