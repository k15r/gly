# agent-access Specification

## Purpose

Lets AI agents (MCP clients such as Claude Code) read the day's schedule and tasks and create, change and delete tasks in WorkDash, with every agent change attributed and kept separate from the user's own undo.

## Requirements

### Requirement: Read the schedule of a day
The system SHALL provide an MCP tool `get_schedule` that returns, for a given date (default: today, local time), the appointments of all visible calendars and the tasks the day view shows for that date.

#### Scenario: Today's schedule
- **WHEN** an agent calls `get_schedule` without arguments
- **THEN** it receives today's appointments in start order and today's due and overdue open tasks, matching the day view

#### Scenario: Another day
- **WHEN** an agent calls `get_schedule` with `date: "2026-10-28"`
- **THEN** it receives the appointments and tasks due on 28 October, without overdue tasks

#### Scenario: No calendar access
- **WHEN** the agent process has no calendar access
- **THEN** `get_schedule` still returns the tasks, and reports that appointments are unavailable because calendar access is missing

### Requirement: Appointment details in the schedule
Each appointment returned by `get_schedule` SHALL include title, start, end, all-day flag, cancelled flag, calendar name, location, organizer, attendees, and how it counts for free time (blocks, maybe, free) with the reason (automatic or override).

#### Scenario: Appointment with an override
- **WHEN** one occurrence of a recurring meeting is set to Ignore and an agent calls `get_schedule` for that day
- **THEN** that appointment counts as free with the reason override, and the other appointments carry their automatic classification

### Requirement: Planning data in the schedule
The `get_schedule` response SHALL include the day's free time and, for today, the Today list (with why each task is there, the work needed today and whether it can't fit) and the Coming up list (with each task's start-by day).

#### Scenario: Planning data
- **WHEN** an agent calls `get_schedule` for today
- **THEN** it receives the free time left today, the Today tasks with reason, effort, work needed today and can't-fit flag, and the Coming up tasks with start-by day

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
The system SHALL provide an MCP tool `get_task` that returns one task by id with all its fields: id, title, notes, status, priority, due date and optional time, snooze date, tags, created and modified time, and who last modified it, plus the links in its notes and its backlinks.

#### Scenario: Existing task
- **WHEN** an agent calls `get_task` with the id of an existing task
- **THEN** it receives all fields of that task

#### Scenario: Unknown or deleted task
- **WHEN** an agent calls `get_task` with an id that doesn't exist or was deleted
- **THEN** it receives a "not found" error

#### Scenario: Task with links
- **WHEN** a task's notes link to a page and another page links to the task
- **THEN** `get_task` returns the first page under links and the second under backlinks, each with id, kind and title

### Requirement: Create a task
The system SHALL provide an MCP tool `create_task` that creates an open task with a required title and optional notes, priority, due date (with optional time) and tags. The same validation as in the app SHALL apply. The response SHALL contain the new task's id and fields.

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
Every tool SHALL describe its purpose, its inputs with types and allowed values, and its output, in the tool list the MCP server provides. Dates SHALL be `YYYY-MM-DD` and times `HH:mm` in local time, and the descriptions SHALL say so. Descriptions of tools that take markdown SHALL explain how to write links.

#### Scenario: Agent discovers the tools
- **WHEN** an MCP client lists the tools
- **THEN** it receives `get_schedule`, `list_tasks`, `get_task`, `create_task`, `update_task`, `delete_task`, `list_tags`, `create_page`, `get_page`, `update_page`, `delete_page`, `search`, `get_context`, `get_tag_page` and `update_tag_page`, each with an input schema and description

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
- **THEN** it can't connect, and no request reaches WorkDash

### Requirement: Pages over MCP
The system SHALL provide MCP tools to create a page (required title, optional markdown text and tags), read a page by id (all fields, links and backlinks), update the given fields of a page (one change in the history per call), and delete a page (recoverable). The same validation as in the app SHALL apply, and changes SHALL be attributed to the agent.

#### Scenario: Meeting notes from an agent
- **WHEN** an agent calls `create_page` with title "Atlas sync 2026-10-27", markdown text and tag `project/atlas`
- **THEN** the page exists, appears in the app without refresh, and the history records the agent as writer

#### Scenario: Partial page update
- **WHEN** an agent calls `update_page` with only new text
- **THEN** only the text changes; title and tags stay

### Requirement: Links written by agents
Markdown sent by agents SHALL accept links as `[[…]]` (resolved as typed links are, including the `page:`, `task:` and `tag:` prefixes and the `tag/path/Title` form) and in the canonical link form that tools return. Responses SHALL return markdown in the canonical form, and SHALL report links that stayed unresolved, each with its candidates (id, kind, title, tags) when several items matched.

#### Scenario: Agent links by title
- **WHEN** an agent creates a task with notes "details in [[Atlas architecture]]" and that page exists
- **THEN** the task links to the page, and the response shows the link in canonical form

#### Scenario: Unresolved link reported
- **WHEN** an agent writes `[[Atlas roadmap]]` and no such page exists
- **THEN** the change is saved with a missing-page link, and the response lists "Atlas roadmap" as unresolved

#### Scenario: Ambiguous link with candidates
- **WHEN** an agent writes `[[Goals]]` and pages "Goals" exist under `person/alex` and `person/sam`
- **THEN** the response lists "Goals" as unresolved with both pages as candidates, and a retry with `[[person/alex/Goals]]` links the first

### Requirement: Search over MCP
The system SHALL provide an MCP tool `search` that runs the full-text search with an optional kind filter (pages, tasks, tags) and a limit, returning id, kind, title and an excerpt for each result.

#### Scenario: Find notes
- **WHEN** an agent calls `search` with query `load test` and kind `page`
- **THEN** it receives matching pages with excerpts, best matches first

### Requirement: Context of an item
The system SHALL provide an MCP tool `get_context` that returns, for a page, task or tag, everything connected to it: outgoing links, backlinks and, for tags, the tagged items; each with id, kind and title.

#### Scenario: Context of a page
- **WHEN** an agent calls `get_context` for a page that links to one task and is linked from two pages
- **THEN** it receives the task under links and the two pages under backlinks

### Requirement: Tag pages over MCP
The system SHALL provide MCP tools `get_tag_page` (description and tagged items, grouped as on the tag page) and `update_tag_page` (replace the description).

#### Scenario: Describe a project
- **WHEN** an agent calls `update_tag_page` for `project/atlas` with a markdown description
- **THEN** the tag page of `project/atlas` shows that description

### Requirement: Effort over MCP
Task results SHALL include the effort (or null), and `create_task` and `update_task` SHALL accept an optional effort (`XS`, `S`, `M`, `L`, `XL`; null on update removes it).

#### Scenario: Agent estimates a task
- **WHEN** an agent creates a task with `effort: "M"`
- **THEN** the task has effort `M` and is planned in the day view's Today or Coming up list if it is due within the horizon

### Requirement: Links carry display names for agents
Links and backlinks in tool responses SHALL include the target's tags and a `display` name that adds the duplicate qualifier when the title is not unique. `create_page` with a title that other pages already use SHALL succeed and name those pages in its response.

#### Scenario: Two Goals pages
- **WHEN** an agent reads a page that links to the "Goals" page of `person/alex` while another "Goals" page exists
- **THEN** the link in the response has `display` "Goals · person/alex" and the page's tags
