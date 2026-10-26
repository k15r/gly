import Foundation
import GRDB

/// Filter for searching tasks (MCP `list_tasks`, design M3). All conditions are combined with AND.
public struct TaskFilter: Equatable {
    /// Statuses to include. Empty = all.
    public var statuses: Set<TaskStatus>
    public var tag: TagName?
    /// Due on or before / on or after this day (YYYY-MM-DD). Tasks without due date don't match either.
    public var dueBefore: String?
    public var dueAfter: String?
    /// Text contained in the title (case-insensitive for ASCII, like SQLite's LIKE).
    public var text: String?
    public var limit: Int

    public init(statuses: Set<TaskStatus> = [.open, .snoozed], tag: TagName? = nil, dueBefore: String? = nil,
                dueAfter: String? = nil, text: String? = nil, limit: Int = 50) {
        self.statuses = statuses; self.tag = tag; self.dueBefore = dueBefore; self.dueAfter = dueAfter
        self.text = text; self.limit = limit
    }
}

public struct TaskPage: Equatable {
    public let tasks: [TaskItem]
    /// More tasks match than `limit`.
    public let hasMore: Bool
}

extension TaskQueries {
    /// Open/snoozed tasks first in task-list order, then done and dropped tasks, most recent first.
    static let findOrderSQL = """
        CASE i.status WHEN 'done' THEN 1 WHEN 'dropped' THEN 2 ELSE 0 END,
        CASE WHEN i.status IN ('open', 'snoozed') THEN
            CASE i.priority WHEN 'urgent' THEN 4 WHEN 'high' THEN 3 WHEN 'normal' THEN 2 WHEN 'low' THEN 1 ELSE 0 END END DESC,
        CASE WHEN i.status IN ('open', 'snoozed') THEN i.due_day IS NULL END,
        CASE WHEN i.status IN ('open', 'snoozed') THEN i.due_day END,
        CASE WHEN i.status IN ('open', 'snoozed') THEN i.due_time IS NOT NULL END,
        CASE WHEN i.status IN ('open', 'snoozed') THEN i.due_time END,
        CASE WHEN i.status IN ('open', 'snoozed') THEN i.created_at END,
        COALESCE(i.completed_at, i.modified_at) DESC
        """

    public static func find(_ db: Database, _ filter: TaskFilter) throws -> TaskPage {
        var conditions = ["i.kind = 'task'"]
        var arguments: [String: DatabaseValueConvertible?] = [:]
        if !filter.statuses.isEmpty {
            let names = filter.statuses.map(\.rawValue).sorted()
            conditions.append("i.status IN (\(names.indices.map { ":s\($0)" }.joined(separator: ", ")))")
            for (n, name) in names.enumerated() { arguments["s\(n)"] = name }
        }
        if let tag = filter.tag {
            conditions.append("i.id IN (SELECT it.item_id FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE t.name_key = :tagKey OR t.name_key LIKE :tagPattern ESCAPE '\\')")
            arguments["tagKey"] = tag.key
            arguments["tagPattern"] = TagFilter.descendantPattern(tag)
        }
        if let d = filter.dueBefore { conditions.append("i.due_day <= :dueBefore"); arguments["dueBefore"] = d }
        if let d = filter.dueAfter { conditions.append("i.due_day >= :dueAfter"); arguments["dueAfter"] = d }
        if let text = filter.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
            conditions.append("i.title LIKE :text ESCAPE '\\'")
            arguments["text"] = "%" + TagFilter.escapeLike(text) + "%"
        }
        let limit = max(1, filter.limit)
        arguments["limit"] = limit + 1
        let tasks = try fetchTasks(db, sql: """
            SELECT i.* FROM live_items i WHERE \(conditions.joined(separator: " AND "))
            ORDER BY \(findOrderSQL) LIMIT :limit
            """, arguments: StatementArguments(arguments))
        return TaskPage(tasks: Array(tasks.prefix(limit)), hasMore: tasks.count > limit)
    }
}

/// A tag with its number of open tasks (MCP `list_tags`).
public struct TagCount: Equatable {
    public let name: String
    public let openCount: Int
}

extension TagQueries {
    /// All live tags (optionally below/starting with `prefix`), with open-task counts; unused tags included so agents reuse them.
    /// "Open" as in the tag list: open, or snoozed with the snooze date reached (`today` = YYYY-MM-DD).
    public static func list(_ db: Database, prefix: String? = nil, today: String) throws -> [TagCount] {
        let key = TagName.key(for: (prefix ?? "").trimmingCharacters(in: .whitespaces))
        let rows = try Row.fetchAll(db, sql: """
            SELECT t.name,
                   (SELECT COUNT(*) FROM live_item_tags it JOIN live_items i ON i.id = it.item_id
                    WHERE it.tag_id = t.id AND i.kind = 'task' AND \(TaskQueries.effectivelyOpenSQL)) AS open_count
            FROM live_tags t
            WHERE t.archived = 0 AND t.name_key LIKE :pattern ESCAPE '\\'
            ORDER BY t.name_key
            """, arguments: ["pattern": TagFilter.escapeLike(key) + "%", "today": today])
        return rows.map { TagCount(name: $0["name"], openCount: $0["open_count"]) }
    }
}
