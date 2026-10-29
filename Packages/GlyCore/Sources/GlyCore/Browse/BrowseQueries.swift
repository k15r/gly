import Foundation
import GRDB

/// One result of the item browser (item-browser I1): the fields every row shows, plus the task for task rows.
public struct BrowseItem: Equatable, Identifiable {
    public let id: String
    public let kind: ItemKind
    public let title: String
    /// The start of the text (enough for an excerpt).
    public let textStart: String
    /// The start of the text as one line; computed when a row shows it, not for every result.
    public var excerpt: String { Excerpt.of(textStart) }
    public let tags: [String]
    public let createdAt: Date
    public let modifiedAt: Date
    public let modifiedBy: String
    /// Bookmarks: the URL.
    public let url: String?
    /// Tasks: the task, for the task row (status bar, chips, quick actions).
    public let task: TaskItem?

    public var linkRef: LinkRef { LinkRef(kind: kind.linkKind, id: id, title: title) }
}

/// Result orders (item-browser I5).
public enum ItemSort: String, Codable, CaseIterable, Sendable {
    /// Full-text rank; without text the same as `changed`.
    case relevance
    /// Last change first.
    case changed
    /// Earliest due date first, items without due date last.
    case due
    case title
    /// Open tasks in task-list order, then done and dropped tasks, most recently finished first; other kinds after.
    case taskOrder
}

public enum BrowseQueries {
    /// Live items matching `query`, in `sort` order. `now` and `calendar` place "today", "this week" and the change windows.
    public static func items(_ db: Database, _ query: ItemQuery, sort: ItemSort, now: Date = Date(), calendar: Calendar = .current,
                             limit: Int? = nil) throws -> [BrowseItem] {
        guard let (sql, arguments) = statement(query, sort: sort, now: now, calendar: calendar, limit: limit) else { return [] }
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
        guard !rows.isEmpty else { return [] }
        let tags = try TaskQueries.tagsByItem(db, ids: rows.map { $0["id"] as String })
        let tasks = Dictionary(try TaskQueries.tasks(from: rows.filter { ($0["kind"] as String) == "task" }, db: db).map { ($0.id, $0) },
                               uniquingKeysWith: { a, _ in a })
        return rows.compactMap { r in
            guard let kind = ItemKind(storedKind: r["kind"]) else { return nil }
            let id: String = r["id"]
            return BrowseItem(id: id, kind: kind, title: r["title"], textStart: String((r["body"] as String? ?? "").prefix(400)), tags: tags[id] ?? [],
                              createdAt: r["created_at"], modifiedAt: r["modified_at"], modifiedBy: r["modified_by"],
                              url: r["url"], task: tasks[id])
        }
    }

    /// How many items match (sidebar counts).
    public static func count(_ db: Database, _ query: ItemQuery, now: Date = Date(), calendar: Calendar = .current) throws -> Int {
        guard let (sql, arguments) = statement(query, sort: .changed, now: now, calendar: calendar, limit: nil) else { return 0 }
        return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM (\(sql))", arguments: arguments) ?? 0
    }

    /// AND-ed conditions with their arguments.
    struct Conditions {
        var sql: [String] = []
        var arguments: StatementArguments = []
        mutating func add(_ condition: String, _ args: StatementArguments = []) { sql.append(condition); arguments += args }
        static func list(_ n: Int) -> String { Array(repeating: "?", count: n).joined(separator: ",") }
    }

    /// The SQL for a query; nil when it can't match anything (text without searchable words).
    static func statement(_ q: ItemQuery, sort: ItemSort, now: Date, calendar: Calendar, limit: Int?) -> (String, StatementArguments)? {
        var w = Conditions()
        kindAndTagConditions(q, into: &w)
        taskConditions(q, today: LocalDay(date: now, calendar: calendar), calendar: calendar, into: &w)
        otherConditions(q, now: now, calendar: calendar, into: &w)

        var from = "live_items i"
        var arguments = w.arguments
        let text = q.text.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            guard let match = SearchQueries.ftsQuery(text) else { return nil }
            from += """
                 JOIN (SELECT owner_id, bm25(search_index, 0, 0, 0, 10.0, 1.0) AS rank FROM search_index
                       WHERE search_index MATCH ? AND owner_table = 'items') s ON s.owner_id = i.id
                """
            arguments = StatementArguments([match]) + arguments
        }
        var sql = "SELECT i.* FROM \(from) WHERE " + w.sql.joined(separator: " AND ") + " ORDER BY " + order(sort, ranked: !text.isEmpty)
        if let limit { sql += " LIMIT \(max(limit, 0))" }
        return (sql, arguments)
    }

    /// Kinds (meetings only with notes, as in search and the tag tree), tags with descendants, exclusions, untagged.
    static func kindAndTagConditions(_ q: ItemQuery, into w: inout Conditions) {
        let kinds = q.kinds.isEmpty ? Set(ItemKind.allCases) : q.kinds
        let kindSQL = ItemKind.allCases.filter(kinds.contains).map { k in
            k == .meeting ? "(i.kind = 'event_note' AND i.body != '')" : "i.kind = '\(k.storedKind)'"
        }
        w.add("(" + kindSQL.joined(separator: " OR ") + ")")
        for name in q.tags { if let t = try? TagName(name) { let f = TagFilter(t); w.add(f.sql, f.arguments) } }
        for name in q.excludedTags { if let t = try? TagName(name) { let f = TagFilter(t); w.add("NOT " + f.sql, f.arguments) } }
        if q.untagged { w.add("i.id NOT IN (SELECT item_id FROM live_item_tags)") }
    }

    /// Status leaves other kinds alone; due, priority and effort need a task.
    static func taskConditions(_ q: ItemQuery, today: LocalDay, calendar: Calendar, into w: inout Conditions) {
        if !q.statuses.isEmpty {
            let names = TaskStatus.allCases.filter(q.statuses.contains).map(\.rawValue)
            w.add("(i.kind != 'task' OR i.status IN (\(Conditions.list(names.count))))", StatementArguments(names))
        }
        switch q.due {
        case .overdue?: w.add("(i.kind = 'task' AND i.status IN ('open', 'snoozed') AND i.due_day < ?)", [today.description])
        case .today?: w.add("(i.kind = 'task' AND i.due_day = ?)", [today.description])
        case .week?:
            w.add("(i.kind = 'task' AND i.due_day >= ? AND i.due_day <= ?)", [today.description, today.adding(days: 6, calendar: calendar).description])
        case .none?: w.add("(i.kind = 'task' AND i.due_day IS NULL)")
        case nil: break
        }
        if !q.priorities.isEmpty {
            let names = Priority.allCases.filter(q.priorities.contains).map(\.rawValue)
            w.add("(i.kind = 'task' AND COALESCE(i.priority, 'none') IN (\(Conditions.list(names.count))))", StatementArguments(names))
        }
        if !q.efforts.isEmpty {
            let names = Effort.allCases.filter(q.efforts.contains).map(\.rawValue)
            w.add("(i.kind = 'task' AND i.effort IN (\(Conditions.list(names.count))))", StatementArguments(names))
        }
    }

    /// Last change, author and bookmark host (a host includes its subdomains).
    static func otherConditions(_ q: ItemQuery, now: Date, calendar: Calendar, into w: inout Conditions) {
        if let changed = q.changed {
            let since: Date = switch changed {
            case .today: calendar.startOfDay(for: now)
            case .days7: calendar.date(byAdding: .day, value: -7, to: now) ?? now
            case .days30: calendar.date(byAdding: .day, value: -30, to: now) ?? now
            }
            w.add("i.modified_at >= ?", [since])
        }
        switch q.author {
        case .agent?: w.add("i.modified_by LIKE 'agent:%'")
        case .me?: w.add("i.modified_by NOT LIKE 'agent:%'")
        case nil: break
        }
        if !q.hosts.isEmpty {
            let one = "(i.url LIKE ? ESCAPE '\\' OR i.url LIKE ? ESCAPE '\\' OR i.url LIKE ? ESCAPE '\\' OR i.url LIKE ? ESCAPE '\\')"
            w.add("(i.kind = 'bookmark' AND (" + Array(repeating: one, count: q.hosts.count).joined(separator: " OR ") + "))",
                  StatementArguments(q.hosts.flatMap { h -> [String] in
                      let e = TagFilter.escapeLike(h)
                      return ["%://\(e)", "%://\(e)/%", "%.\(e)", "%.\(e)/%"]
                  }))
        }
    }

    static func order(_ sort: ItemSort, ranked: Bool) -> String {
        switch sort {
        case .relevance: ranked ? "s.rank, i.modified_at DESC" : "i.modified_at DESC"
        case .changed: "i.modified_at DESC"
        case .due: "i.due_day IS NULL, i.due_day, i.due_time IS NULL, i.due_time, i.modified_at DESC"
        case .title: "i.title COLLATE NOCASE, i.modified_at DESC"
        case .taskOrder: "i.kind != 'task', " + TaskQueries.findOrderSQL + ", i.modified_at DESC"
        }
    }
}
