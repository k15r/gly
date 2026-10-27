import Foundation
import GRDB

public enum TaskListMode: String, CaseIterable, Codable, Sendable {
    case open, done, dropped
}

/// A task in the day view, with whether it is overdue relative to the displayed day.
public struct DayTask: Equatable, Identifiable {
    public var id: String { task.id }
    public let task: TaskItem
    public let isOverdue: Bool
    public init(task: TaskItem, isOverdue: Bool) { self.task = task; self.isOverdue = isOverdue }
}

public enum TaskQueries {
    /// A task counts as open if it is `open`, or `snoozed` and its snooze date has arrived.
    /// Needs a named argument `:today` (YYYY-MM-DD). Columns refer to the `i` alias.
    public static let effectivelyOpenSQL =
        "(i.status = 'open' OR (i.status = 'snoozed' AND i.snoozed_until <= :today))"

    /// Sort order for open tasks (design L3): priority desc, due day (none last), due time (whole day first), created.
    static let openOrderSQL = """
        CASE i.priority WHEN 'urgent' THEN 4 WHEN 'high' THEN 3 WHEN 'normal' THEN 2 WHEN 'low' THEN 1 ELSE 0 END DESC,
        i.due_day IS NULL, i.due_day, i.due_time IS NOT NULL, i.due_time, i.created_at
        """

    /// Task list (specs/tasks "Task list"), optionally filtered by tag (including descendants).
    public static func taskList(_ db: Database, mode: TaskListMode, today: LocalDay, tag: TagName? = nil) throws -> [TaskItem] {
        var conditions = ["i.kind = 'task'"]
        var arguments: [String: DatabaseValueConvertible?] = ["today": today.description]
        let order: String
        switch mode {
        case .open:
            // Snoozed tasks are regular list entries (specs/tasks "Task list"); only the day view hides them.
            conditions.append("i.status IN ('open', 'snoozed')")
            order = openOrderSQL
        case .done:
            conditions.append("i.status = 'done'")
            order = "i.completed_at DESC"
        case .dropped:
            conditions.append("i.status = 'dropped'")
            order = "i.modified_at DESC"
        }
        var sql = "SELECT i.* FROM live_items i WHERE \(conditions.joined(separator: " AND "))"
        if let tag {
            // Same condition as TagFilter, with named arguments so it combines with :today.
            sql += " AND i.id IN (SELECT it.item_id FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id"
                + " WHERE t.name_key = :tagKey OR t.name_key LIKE :tagPattern ESCAPE '\\')"
            arguments["tagKey"] = tag.key
            arguments["tagPattern"] = TagFilter.descendantPattern(tag)
        }
        sql += " ORDER BY \(order)"
        return try fetchTasks(db, sql: sql, arguments: StatementArguments(arguments))
    }

    /// Tasks for the day view (specs/day-view "Tasks for the day"): open tasks due on `day`,
    /// plus overdue ones when `day` is `today`. Tasks still snoozed on `day` are left out.
    /// Open tasks for a day view: for today and later days also those overdue as seen from that day (a forecast that assumes
    /// nothing is done before it, specs/day-view "Tasks for the day"); for past days only the tasks due that day.
    public static func tasksForDay(_ db: Database, day: LocalDay, today: LocalDay) throws -> [DayTask] {
        let includeOverdue = day >= today
        let dueCondition = includeOverdue ? "i.due_day <= :day" : "i.due_day = :day"
        let tasks = try fetchTasks(db, sql: """
            SELECT i.* FROM live_items i
            WHERE i.kind = 'task' AND \(effectivelyOpenSQL) AND \(dueCondition)
            ORDER BY \(openOrderSQL)
            """, arguments: ["today": day.description, "day": day.description])
        return tasks.map { t in
            DayTask(task: t, isOverdue: includeOverdue && (t.due.map { $0.day < day.description } ?? false))
        }
    }

    public static func task(_ db: Database, id: String) throws -> TaskItem? {
        try fetchTasks(db, sql: "SELECT i.* FROM live_items i WHERE i.id = ? AND i.kind = 'task'", arguments: [id]).first
    }

    // MARK: - Mapping

    /// Live tag names per item, in name order.
    public static func tagsByItem(_ db: Database, ids: [String]) throws -> [String: [String]] {
        var tagsByItem: [String: [String]] = [:]
        // Chunked to stay below SQLite's variable limit.
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let marks = chunk.map { _ in "?" }.joined(separator: ",")
            for r in try Row.fetchAll(db, sql: """
                SELECT it.item_id, t.name FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id
                WHERE it.item_id IN (\(marks)) ORDER BY t.name_key
                """, arguments: StatementArguments(chunk)) {
                tagsByItem[r["item_id"], default: []].append(r["name"])
            }
        }
        return tagsByItem
    }

    static func fetchTasks(_ db: Database, sql: String, arguments: StatementArguments) throws -> [TaskItem] {
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
        guard !rows.isEmpty else { return [] }
        let tagsByItem = try tagsByItem(db, ids: rows.map { $0["id"] as String })
        return rows.map { r in
            let dueDay: String? = r["due_day"]
            return TaskItem(
                id: r["id"], title: r["title"], body: r["body"],
                status: TaskStatus(rawValue: r["status"] ?? "open") ?? .open,
                priority: Priority(rawValue: r["priority"] ?? "none") ?? .none,
                due: dueDay.map { Due(day: $0, time: r["due_time"]) },
                snoozedUntil: r["snoozed_until"], tags: tagsByItem[r["id"]] ?? [],
                createdAt: r["created_at"], modifiedAt: r["modified_at"], modifiedBy: r["modified_by"],
                completedAt: r["completed_at"],
                effort: (r["effort"] as String?).flatMap(Effort.init(rawValue:)),
                snoozeEndedOn: r["snooze_ended_on"])
        }
    }
}
