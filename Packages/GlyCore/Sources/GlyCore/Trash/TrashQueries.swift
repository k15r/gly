import Foundation
import GRDB

/// A deleted page, task or meeting notes document (specs/trash "Trash contents", design T1).
public struct TrashEntry: Equatable, Identifiable {
    public let id: String
    public let kind: LinkRef.Kind
    public let title: String
    /// The tags the item had when it was deleted.
    public let tags: [String]
    public let excerpt: String
    /// Tasks only.
    public let status: TaskStatus?
    public let deletedAt: Date
    /// The writer of the delete, nil for items without a delete entry in the change log.
    public let deletedBy: String?
    /// The change-log batch that deleted the item (what a restore reverts), nil as above.
    public let batch: String?
}

public enum TrashQueries {
    /// How far back the Trash looks by default (specs/trash "Deleted items are kept").
    public static let defaultDays = 30

    /// Deleted pages and tasks, most recently deleted first; `since` nil = all.
    public static func list(_ db: Database, since: Date? = nil) throws -> [TrashEntry] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT i.id, i.kind, i.title, i.body, i.status, i.deleted_at FROM items i
            WHERE (i.kind IN ('info', 'task') OR (i.kind = 'event_note' AND i.body != '')) AND i.deleted_at IS NOT NULL AND (? IS NULL OR i.deleted_at >= ?)
            ORDER BY i.deleted_at DESC
            """, arguments: [since, since])
        return try rows.map { r in
            let id: String = r["id"]
            let delete = try deleteEntry(db, itemID: id)
            return TrashEntry(id: id, kind: LinkRef.Kind(itemKind: r["kind"]), title: r["title"],
                              tags: try delete.map { try tags(db, deletedIn: $0.batch, itemID: id) } ?? [],
                              excerpt: TreeLeaf.excerpt(of: r["body"] ?? ""),
                              status: (r["status"] as String?).flatMap(TaskStatus.init(rawValue:)),
                              deletedAt: delete?.at ?? r["deleted_at"], deletedBy: delete?.writer, batch: delete?.batch)
        }
    }

    /// Number of deleted pages and tasks deleted before `date` ("Show older (n)").
    public static func count(_ db: Database, before date: Date) throws -> Int {
        try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM items WHERE (kind IN ('info', 'task') OR (kind = 'event_note' AND body != '')) AND deleted_at IS NOT NULL AND deleted_at < ?
            """, arguments: [date]) ?? 0
    }

    /// The deleted page or task with this id, or nil when it is live, unknown or another kind.
    public static func entry(_ db: Database, id: String) throws -> TrashEntry? {
        guard try Bool.fetchOne(db, sql: """
            SELECT 1 FROM items WHERE id = ? AND (kind IN ('info', 'task') OR (kind = 'event_note' AND body != '')) AND deleted_at IS NOT NULL
            """,
                                arguments: [id]) == true else { return nil }
        return try list(db).first { $0.id == id }
    }

    /// The latest change that set the item's `deleted_at` (a delete, or a redo of one) and wasn't undone.
    static func deleteEntry(_ db: Database, itemID: String) throws -> (batch: String, at: Date, writer: String)? {
        try Row.fetchOne(db, sql: """
            SELECT batch, at, writer FROM change_log
            WHERE table_name = 'items' AND row_id = ? AND field = 'deleted_at' AND new_value IS NOT NULL AND undone = 0
            ORDER BY seq DESC LIMIT 1
            """, arguments: [itemID]).map { ($0["batch"], $0["at"], $0["writer"]) }
    }

    /// Names of the tags whose assignment to the item was tombstoned in `batch`.
    static func tags(_ db: Database, deletedIn batch: String, itemID: String) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT DISTINCT t.name FROM change_log c
            JOIN item_tags it ON it.id = c.row_id JOIN tags t ON t.id = it.tag_id
            WHERE c.batch = ? AND c.table_name = 'item_tags' AND it.item_id = ?
            ORDER BY t.name_key
            """, arguments: [batch, itemID])
    }
}

/// Who made a change, for people (design T3): "you", "Claude Code", "Joule", "gly".
public enum WriterName {
    /// - Parameter writer: e.g. `user@mac-1a2b3c`, `agent:claude-code@mac-1a2b3c`, `system@mac-1a2b3c`.
    public static func display(_ writer: String?) -> String {
        guard let writer else { return "unknown" }
        let who = writer.split(separator: "@", maxSplits: 1).first.map(String.init) ?? writer
        if who == "user" { return "you" }
        if who == "system" { return "gly" }
        guard who.hasPrefix("agent:") else { return who }
        let client = String(who.dropFirst("agent:".count))
        if client == "claude-code" { return "Claude Code" }
        return client.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
