import MCP

/// The MCP tools WorkDash offers (specs/agent-access "Tool descriptions guide agents").
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

    static let taskShape = "A task is {id, title, notes, status, priority, due: {day, time?} or null, snoozed_until, tags, created_at, modified_at, modified_by}."

    public static let all: [Tool] = [
        Tool(name: "get_schedule",
             description: "The user's schedule for one day: appointments from all visible calendars (in start order; all-day ones flagged) and the tasks the WorkDash day view shows (due that day; for today also overdue ones, flagged). If calendar access is missing, tasks are still returned and appointments_unavailable explains why. \(dateNote) \(taskShape)",
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
             description: "One task with all fields, by id. \(taskShape)",
             inputSchema: object(["id": string("Task id.")], required: ["id"]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "create_task",
             description: "Create a task. Only the title is required; new tasks are open with priority none unless given. Returns the created task. \(dateNote)",
             inputSchema: object([
                "title": string("Short, actionable title."),
                "notes": string("Details (markdown)."),
                "priority": string("Priority.", enum: priorityValues),
                "due_date": string("Due day (YYYY-MM-DD)."),
                "due_time": string("Due time (HH:mm); needs due_date. Omit for a whole-day due date."),
                "tags": tagsSchema,
             ], required: ["title"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)),
        Tool(name: "update_task",
             description: "Change a task. Only given fields change; all changes are one step in the history. tags replaces the whole tag set. Set due_date to null to remove the due date. status: done = complete, open = reopen, dropped = won't do, snoozed = hide from the day view until snoozed_until (required then). Returns the updated task. \(dateNote)",
             inputSchema: object([
                "id": string("Task id."),
                "title": string("New title."),
                "notes": string("New notes (markdown); replaces the old notes."),
                "priority": string("New priority.", enum: priorityValues),
                "due_date": nullableString("New due day (YYYY-MM-DD), or null to remove the due date."),
                "due_time": string("Due time (HH:mm); only together with due_date. Omit for whole day."),
                "tags": tagsSchema,
                "status": string("New status.", enum: statusValues),
                "snoozed_until": string("Day the task comes back (YYYY-MM-DD); required with status snoozed."),
             ], required: ["id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
        Tool(name: "delete_task",
             description: "Delete a task. It disappears from all views; its data stays in WorkDash's history and can be restored there. Prefer update_task with status dropped for tasks that won't be done.",
             inputSchema: object(["id": string("Task id.")], required: ["id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)),
        Tool(name: "list_tags",
             description: "Existing tags with their number of open tasks (unused tags included), optionally only those starting with a prefix. Use it to reuse existing tags instead of inventing new ones.",
             inputSchema: object(["prefix": string("Only tags starting with this text, e.g. \"person/\".")]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
    ]
}
