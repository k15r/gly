// Tool and server descriptions are prose for agents, kept as one string each; wrapping them would only hurt editing.
// swiftlint:disable line_length
import MCP
import GlyCore

/// The MCP tools gly offers (specs/agent-access "Tool descriptions guide agents").
public enum ToolDefinitions {
    static let dateNote = "Dates are YYYY-MM-DD and times HH:mm, both in the Mac's local time."
    static let statusValues: [Value] = ["open", "snoozed", "done", "dropped"]
    static let priorityValues: [Value] = ["none", "low", "normal", "high", "urgent"]

    static func object(_ properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = ["type": "object", "properties": .object(properties), "additionalProperties": false]
        if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
        return .object(schema)
    }
    static func string(_ description: String, enum values: [Value]? = nil) -> Value {
        var s: [String: Value] = ["type": "string", "description": .string(description)]
        if let values { s["enum"] = .array(values) }
        return .object(s)
    }
    static func nullableString(_ description: String) -> Value {
        .object(["type": .array(["string", "null"]), "description": .string(description)])
    }
    static let tagsSchema: Value = .object([
        "type": "array", "items": ["type": "string"],
        "description": "Hierarchical tag names like \"project/atlas\" or \"person/alex\" (segments separated by /, none empty). Prefer existing tags (see list_tags).",
    ])

    static let taskShape = "A task is {id, title, notes, status, priority, due: {day, time?} or null, snoozed_until, effort (XS/S/M/L/XL or null), tags, created_at, modified_at, modified_by}."
    static let effortSchema: Value = .object(["type": .array(["string", "null"]), "enum": ["XS", "S", "M", "L", "XL", .null],
                                              "description": "How much work the task is: XS ≈ 30 min, S ≈ 2 h, M ≈ half a day, L ≈ a day, XL ≈ several days (the user can tune these). null removes it."])
    static let linkNote = "Markdown may link to pages, tasks and tags: write [[Exact Title]] (resolved if exactly one page, task or tag has that title or name), narrow it with a prefix ([[page:Title]], [[task:Title]], [[tag:project/atlas]]) or a tag path ([[person/alex/Goals]] = the page or task titled Goals that carries the tag person/alex), or reuse the canonical form [label](gly://item/<id>) / [label](gly://tag/<id>) returned by tools. Titles may repeat (e.g. a Goals page per person). Resolution happens once; afterwards the link points to the id. Unresolved links stay as 'missing page' links and are listed in `unresolved` and `unresolved_links` (with candidates when several items matched – retry with a tag path or prefix). Ordinary web links ([text](https://…)) are fine too."
    static let pageShape = "A page is {id, title, text, tags, created_at, modified_at, modified_by, links: [{id, kind, title, display, tags, state}], backlinks: [{id, kind, title, display, tags, excerpt}]}; kind is page, task or tag; state is live, deleted or missing; display adds a qualifier (\"Goals · person/alex\") when titles repeat."

    public static let all: [Tool] = [
        Tool(name: "get_schedule",
             description: "The user's schedule for one day: appointments from all visible calendars (in start order; all-day ones flagged; counts_as = blocks/maybe/free for the user's free time, with reason; has_notes when the meeting has notes; calendar_id, base_id and original_start identify it for get_meeting_notes / update_meeting_notes) and the tasks the gly day view shows (due that day; for today and later days also the ones overdue as seen from that day, flagged), plus free_minutes (free working time that day, for today from now on). For today and later days also: today (that day's tasks overdue, due that day, or needing work that day; reason = overdue/due_today/needs_work, needed_today_minutes = minimum work that day to finish on time, cant_fit when even all free time until the due date isn't enough), needed_today_minutes (sum) and without_estimate, and coming_up (other tasks due within the planning horizon after that day, each with start_by = last day to start). A later day is a forecast: it assumes nothing is done before it. If calendar access is missing, tasks are still returned and appointments_unavailable explains why. \(dateNote) \(taskShape)",
             inputSchema: object(["date": string("Day to show (YYYY-MM-DD). Default: today.")]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "list_tasks",
             description: "Search tasks. Filters combine with AND. status 'open' (default) includes snoozed tasks; 'all' returns every status. Sorted like the task list (urgent first, then by due date), done/dropped last. Returns at most `limit` tasks (default 50) and has_more when there are more. \(dateNote) \(taskShape)",
             inputSchema: object([
                "status": string("Which tasks: open (incl. snoozed), snoozed, done, dropped or all.", enum: ["open", "snoozed", "done", "dropped", "all"]),
                "tag": string("Only tasks with this tag or a tag below it (\"project\" matches \"project/atlas\")."),
                "due_before": string("Only tasks due on or before this day (YYYY-MM-DD)."),
                "due_after": string("Only tasks due on or after this day (YYYY-MM-DD)."),
                "text": string("Only tasks whose title contains this text (case-insensitive)."),
                "limit": .object(["type": "integer", "minimum": 1, "maximum": 500, "description": "Maximum number of tasks (default 50)."]),
             ]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "get_task",
             description: "One task with all fields, by id, plus `links` (what its notes link to) and `backlinks` (what links to it). \(taskShape)",
             inputSchema: object(["id": string("Task id.")], required: ["id"]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "create_task",
             description: "Create a task. Only the title is required; new tasks are open with priority none unless given. Returns the created task. \(dateNote) \(linkNote)",
             inputSchema: object([
                "title": string("Short, actionable title."),
                "notes": string("Details (markdown)."),
                "priority": string("Priority.", enum: priorityValues),
                "due_date": string("Due day (YYYY-MM-DD)."),
                "due_time": string("Due time (HH:mm); needs due_date. Omit for a whole-day due date."),
                "tags": tagsSchema,
                "effort": effortSchema,
             ], required: ["title"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)),
        Tool(name: "update_task",
             description: "Change a task. Only given fields change; all changes are one step in the history. tags replaces the whole tag set. Set due_date to null to remove the due date. status: done = complete, open = reopen, dropped = won't do, snoozed = hide from the day view until snoozed_until (required then). Returns the updated task. \(dateNote) \(linkNote)",
             inputSchema: object([
                "id": string("Task id."),
                "title": string("New title."),
                "notes": string("New notes (markdown); replaces the old notes."),
                "priority": string("New priority.", enum: priorityValues),
                "due_date": nullableString("New due day (YYYY-MM-DD), or null to remove the due date."),
                "due_time": string("Due time (HH:mm); only together with due_date. Omit for whole day."),
                "tags": tagsSchema,
                "status": string("New status.", enum: statusValues),
                "effort": effortSchema,
                "snoozed_until": string("Day the task comes back (YYYY-MM-DD); required with status snoozed."),
             ], required: ["id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
        Tool(name: "delete_task",
             description: "Delete a task. It disappears from all views and goes to the trash, from which restore brings it back. Prefer update_task with status dropped for tasks that won't be done.",
             inputSchema: object(["id": string("Task id.")], required: ["id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)),
        Tool(name: "list_tags",
             description: "Existing tags with their number of open tasks (unused tags included) and colors (color: own palette name or null; effective_color: own, inherited or automatic), optionally only those starting with a prefix. Use it to reuse existing tags instead of inventing new ones.",
             inputSchema: object(["prefix": string("Only tags starting with this text, e.g. \"person/\".")]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "create_page",
             description: "Create an info page (notes, knowledge, meeting notes). Only the title is required. Organize pages with tags (no folders). Returns the page. \(linkNote) \(pageShape)",
             inputSchema: object([
                "title": string("Page title."),
                "text": string("Page text (markdown)."),
                "tags": tagsSchema,
             ], required: ["title"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)),
        Tool(name: "get_page",
             description: "One page by id with its text, tags, links and backlinks. \(pageShape)",
             inputSchema: object(["id": string("Page id.")], required: ["id"]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "update_page",
             description: "Change a page. Only given fields change; one step in the history. text replaces the whole text; tags replaces the tag set. Returns the page. \(linkNote)",
             inputSchema: object([
                "id": string("Page id."),
                "title": string("New title (links to the page follow the rename)."),
                "text": string("New text (markdown)."),
                "tags": tagsSchema,
             ], required: ["id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
        Tool(name: "delete_page",
             description: "Delete a page. It disappears from all views and goes to the trash, from which restore brings it back. Links to it show as 'link target deleted' until then.",
             inputSchema: object(["id": string("Page id.")], required: ["id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)),
        Tool(name: "search",
             description: "Full-text search over pages, tasks and tags (titles, texts, tag descriptions). Case- and accent-insensitive; the last word matches as a prefix. Returns {results: [{id, kind, title, excerpt}]}, grouped by kind (pages, tasks, tags), best matches first within each kind.",
             inputSchema: object([
                "query": string("Words to search for."),
                "kind": string("Only this kind.", enum: ["page", "task", "tag"]),
                "limit": .object(["type": "integer", "minimum": 1, "maximum": 100, "description": "Maximum results per kind (default 10)."]),
             ], required: ["query"]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "get_context",
             description: "Everything connected to a page, task or tag: `links` (what its text links to), `backlinks` (what links to it) and, for tags, `tagged` items (open tasks, pages, finished tasks). Give either id (page or task) or tag (tag name).",
             inputSchema: object([
                "id": string("Page or task id."),
                "tag": string("Tag name, e.g. \"project/atlas\"."),
             ]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "get_tag_page",
             description: "A tag's page: its markdown description, color (own or null) and effective_color, and everything tagged with it or below it, grouped as open_tasks, pages and finished_tasks. Works for group names like \"person\" too. \(taskShape)",
             inputSchema: object(["name": string("Tag name, e.g. \"project/atlas\".")], required: ["name"]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "update_tag_page",
             description: "Replace a tag's page description (markdown) and/or set its color. Creates the tag if it doesn't exist. A tag without its own color inherits the nearest color set above it (person/alex from person), else gets an automatic one. \(linkNote)",
             inputSchema: object([
                "name": string("Tag name."),
                "text": string("New description (markdown)."),
                "color": string("The tag's own color, or automatic to remove it (inherit again).",
                                enum: (TagColor.allCases.map(\.rawValue) + ["automatic"]).map { Value.string($0) }),
             ], required: ["name"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
        Tool(name: "get_meeting_notes",
             description: "A meeting's notes. Recurring meetings share one ever-growing document for the whole series, with dated sections (## Tue 3 Nov), newest on top; one-off meetings have their own. Identify the meeting with calendar_id, base_id and original_start exactly as get_schedule returns them. Returns {title, kind (series|occurrence), text (markdown), section (this meeting's heading), has_notes, tags, id}.",
             inputSchema: object([
                "calendar_id": string("From get_schedule."),
                "base_id": string("From get_schedule."),
                "original_start": string("From get_schedule."),
             ], required: ["calendar_id", "base_id", "original_start"]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "update_meeting_notes",
             description: "Write a meeting's notes (e.g. prep notes). mode append (default) adds the markdown to this meeting's dated section, creating it on top if needed; replace sets the whole document. tags replaces the notes' tags. Identify the meeting with the fields from get_schedule. \(linkNote)",
             inputSchema: object([
                "calendar_id": string("From get_schedule."),
                "base_id": string("From get_schedule."),
                "original_start": string("From get_schedule."),
                "text": string("Markdown to add (append) or the whole document (replace)."),
                "mode": string("append (default) or replace.", enum: ["append", "replace"]),
                "tags": tagsSchema,
             ], required: ["calendar_id", "base_id", "original_start"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)),
        Tool(name: "list_trash",
             description: "List deleted pages and tasks, most recently deleted first: {items: [{id, kind (page|task), title, tags (as when deleted), excerpt, status (tasks), deleted_at (YYYY-MM-DDTHH:mm, local time), deleted_by}], older_count}. By default the last 30 days; older_count says how many older ones exist (all: true lists everything). Nothing in the trash is ever erased.",
             inputSchema: object([
                "all": .object(["type": "boolean", "description": "List all deleted items, not just the last 30 days."]),
             ], required: []),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "restore",
             description: "Restore a deleted page or task by id (from list_trash), with the fields and tags it had when deleted; links to it work again. Use it to fix a wrong delete. Returns the item like get_page / get_task.",
             inputSchema: object(["id": string("Id of the deleted page or task.")], required: ["id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)),
    ]
}
// swiftlint:enable line_length
