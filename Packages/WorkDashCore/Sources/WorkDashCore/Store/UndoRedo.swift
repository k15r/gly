import Foundation
import GRDB

/// Undo/redo per writer on top of the change log (design L6).
///
/// - Undo reverts the writer's most recent batch that is still in effect (a normal change or a redo).
/// - Redo reverts the writer's most recent undo, as long as the writer made no new change after it.
/// - Reverting an insert tombstones the row; nothing is ever hard-deleted.
/// Another writer's batches are never touched.
extension Database {
    static let changeOps = "('insert', 'update', 'delete')"

    /// Undoes the writer's latest change. Returns the reverted batch id, or nil if there's nothing to undo.
    @discardableResult
    public func undo(writer: String, at: Date = Date()) throws -> String? {
        guard let target = try undoTarget(writer: writer) else { return nil }
        var batch = Batch(db: self, writer: writer, at: at)
        batch.updateOp = "undo"
        batch.redoOf = target
        try revert(batch: target, using: batch)
        try execute(sql: "UPDATE change_log SET undone = 1 WHERE batch = ?", arguments: [target])
        return target
    }

    /// Redoes the writer's latest undo. Returns the re-applied batch id, or nil if there's nothing to redo.
    @discardableResult
    public func redo(writer: String, at: Date = Date()) throws -> String? {
        guard let undoRow = try redoTarget(writer: writer) else { return nil }
        let undoBatch: String = undoRow["batch"]
        var batch = Batch(db: self, writer: writer, at: at)
        batch.updateOp = "redo"
        batch.redoOf = undoRow["redo_of"]
        try revert(batch: undoBatch, using: batch)
        try execute(sql: "UPDATE change_log SET undone = 1 WHERE batch = ?", arguments: [undoBatch])
        return undoRow["redo_of"]
    }

    /// The batch the next undo would revert.
    private func undoTarget(writer: String) throws -> String? {
        try String.fetchOne(self, sql: """
            SELECT batch FROM change_log
            WHERE writer = ? AND undone = 0 AND op IN ('insert', 'update', 'delete', 'redo')
            ORDER BY seq DESC LIMIT 1
            """, arguments: [writer])
    }

    /// The undo batch the next redo would revert (columns `batch`, `redo_of`), or nil.
    private func redoTarget(writer: String) throws -> Row? {
        guard let undoRow = try Row.fetchOne(self, sql: """
            SELECT batch, redo_of, MAX(seq) AS seq FROM change_log
            WHERE writer = ? AND op = 'undo' AND undone = 0
            GROUP BY batch ORDER BY seq DESC LIMIT 1
            """, arguments: [writer]) else { return nil }
        // A new change by this writer after the undo clears the redo chain.
        let newer = try Int.fetchOne(self, sql: """
            SELECT COUNT(*) FROM change_log WHERE writer = ? AND seq > ? AND op IN \(Database.changeOps)
            """, arguments: [writer, undoRow["seq"] as Int64]) ?? 0
        return newer == 0 ? undoRow : nil
    }

    /// What the next undo would revert, for the Edit menu, e.g. `Edit “Plan week” (title, due date)`.
    /// Titles are the current ones, i.e. what the user sees.
    public func undoLabel(writer: String) throws -> String? {
        guard let target = try undoTarget(writer: writer) else { return nil }
        // A redo batch re-applies an earlier change; describe that change.
        let original = try String.fetchOne(self, sql: "SELECT redo_of FROM change_log WHERE batch = ? LIMIT 1", arguments: [target])
        return try label(ofBatch: original ?? target)
    }

    /// What the next redo would re-apply.
    public func redoLabel(writer: String) throws -> String? {
        guard let row = try redoTarget(writer: writer), let original: String = row["redo_of"] else { return nil }
        let first = try String.fetchOne(self, sql: "SELECT redo_of FROM change_log WHERE batch = ? AND redo_of IS NOT NULL LIMIT 1", arguments: [original])
        return try label(ofBatch: first ?? original)
    }

    static let fieldLabels: [(column: String, label: String)] = [
        ("title", "title"), ("body", "notes"), ("priority", "priority"), ("due_day", "due date"), ("due_time", "due date"),
    ]

    /// Label of an undone/redone batch (or of the change a redo batch re-applied).
    public func label(ofChange batchID: String) throws -> String {
        let original = try String.fetchOne(self, sql: "SELECT redo_of FROM change_log WHERE batch = ? AND redo_of IS NOT NULL LIMIT 1", arguments: [batchID])
        return try label(ofBatch: original ?? batchID)
    }

    /// Describes a normal change batch by its entries: create / delete / status change / edit of an item.
    public func label(ofBatch batchID: String) throws -> String {
        let entries = try Row.fetchAll(self, sql: "SELECT * FROM change_log WHERE batch = ? ORDER BY seq", arguments: [batchID])
        // The primary row is the first one written; later rows are follow-ups (tag assignments, link label refreshes).
        // Items first, then tag assignments (→ their item), then tags (a tag page edit).
        guard var primary = entries.first(where: { ($0["table_name"] as String) == "items" })
                ?? entries.first(where: { ($0["table_name"] as String) == "item_tags" })
                ?? entries.first(where: { ($0["table_name"] as String) == "tags" }) else { return "change" }
        if (primary["table_name"] as String) == "item_tags",
           let itemID = try String.fetchOne(self, sql: "SELECT item_id FROM item_tags WHERE id = ?", arguments: [primary["row_id"] as String]) {
            primary = Row(["table_name": "items", "row_id": itemID])
        }
        let table: String = primary["table_name"], rowID: String = primary["row_id"]
        let own = entries.filter { ($0["table_name"] as String) == table && ($0["row_id"] as String) == rowID }
        let fields = own.compactMap { $0["field"] as String? }
        let tagsChanged = entries.contains { ($0["table_name"] as String) == "item_tags" }

        if table == "tags" {
            let name = try String.fetchOne(self, sql: "SELECT name FROM tags WHERE id = ?", arguments: [rowID]) ?? "tag"
            return "Edit tag page “\(name)”"
        }
        guard table == "items",
              let item = try Row.fetchOne(self, sql: "SELECT kind, title FROM items WHERE id = ?", arguments: [rowID]) else { return "change" }
        let isPage = (item["kind"] as String) == "info"
        let quoted = (isPage ? "page " : "") + "“\(item["title"] as String)”"
        if own.contains(where: { ($0["op"] as String) == "insert" }) { return "Create \(quoted)" }
        if fields.contains("deleted_at") { return "Delete \(quoted)" }
        if fields.contains("status"), let entry = own.first(where: { ($0["field"] as String?) == "status" }),
           let status = String.fromDatabaseValue(ChangeValue.decode(entry["new_value"])) {
            let verb = ["done": "Complete", "snoozed": "Snooze", "dropped": "Drop", "open": "Reopen"][status] ?? "Status of"
            return "\(verb) \(quoted)"
        }
        var changed: [String] = []
        for f in Database.fieldLabels where fields.contains(f.column) {
            let label = isPage && f.column == "body" ? "text" : f.label
            if !changed.contains(label) { changed.append(label) }
        }
        if tagsChanged { changed.append("tags") }
        return changed.isEmpty ? "Edit \(quoted)" : "Edit \(quoted) (\(changed.joined(separator: ", ")))"
    }

    /// Applies the inverse of every entry of `batchID`, newest first, logging into `batch`.
    private func revert(batch batchID: String, using batch: Batch) throws {
        let entries = try Row.fetchAll(self, sql: "SELECT * FROM change_log WHERE batch = ? ORDER BY seq DESC", arguments: [batchID])
        var tombstoned = Set<String>()
        for entry in entries {
            let table: String = entry["table_name"]
            let rowID: String = entry["row_id"]
            let op: String = entry["op"]
            if op == "insert" {
                // Reverting an insert = tombstone the row once.
                guard tombstoned.insert("\(table)/\(rowID)").inserted else { continue }
                try batch.update(table, id: rowID, ["deleted_at": batch.at])
            } else if let field: String = entry["field"] {
                try batch.update(table, id: rowID, [field: ChangeValue.decode(entry["old_value"])])
            }
        }
    }
}
