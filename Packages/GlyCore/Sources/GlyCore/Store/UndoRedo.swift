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

    /// Recorded work, a set remaining effort or a reset (task-progress P2), named after the task.
    private func workLabel(_ entries: [Row]) throws -> String? {
        guard entries.allSatisfy({ ($0["table_name"] as String) == "task_work" }), let first = entries.first,
              let row = try Row.fetchOne(self, sql: """
                  SELECT w.kind, i.title FROM task_work w JOIN items i ON i.id = w.item_id WHERE w.id = ?
                  """, arguments: [first["row_id"] as String]) else { return nil }
        let title = "“\(row["title"] as String)”"
        if (first["op"] as String) != "insert" {
            // Removing only "done for today" rows of one day is taking back that part; anything wider is a reset.
            let ids = Array(Set(entries.map { $0["row_id"] as String }))
            let marks = ids.map { _ in "?" }.joined(separator: ",")
            let rows = try Row.fetchAll(self, sql: "SELECT kind, day FROM task_work WHERE id IN (\(marks))", arguments: StatementArguments(ids))
            let onePart = rows.allSatisfy { ($0["kind"] as String) == WorkKind.part.rawValue } && Set(rows.map { $0["day"] as String }).count == 1
            return onePart ? "Take back today's part of \(title)" : "Reset progress of \(title)"
        }
        return (row["kind"] as String) == WorkKind.adjust.rawValue ? "Set remaining effort of \(title)" : "Record work on \(title)"
    }

    /// Saved views (item-browser I3): "Save view …", "Delete view …", "Restore view …", "Edit view …".
    private func viewLabel(_ entries: [Row]) throws -> String? {
        guard let first = entries.first, (first["table_name"] as String) == "views",
              let name = try String.fetchOne(self, sql: "SELECT name FROM views WHERE id = ?", arguments: [first["row_id"] as String]) else { return nil }
        let quoted = "view “\(name)”"
        if entries.contains(where: { ($0["op"] as String) == "insert" }) { return "Save \(quoted)" }
        if let entry = entries.first(where: { ($0["field"] as String?) == "deleted_at" }) {
            return ChangeValue.decode(entry["new_value"]).isNull ? "Restore \(quoted)" : "Delete \(quoted)"
        }
        return "Edit \(quoted)"
    }

    /// bookmarks B2: "Add bookmark …", "Delete bookmark …", "Restore bookmark …", "Edit bookmark …".
    private static func bookmarkLabel(_ own: [Row], title: String) -> String {
        let quoted = "bookmark “\(title)”"
        if own.contains(where: { ($0["op"] as String) == "insert" }) { return "Add \(quoted)" }
        if let entry = own.first(where: { ($0["field"] as String?) == "deleted_at" }) {
            return ChangeValue.decode(entry["new_value"]).isNull ? "Restore \(quoted)" : "Delete \(quoted)"
        }
        return "Edit \(quoted)"
    }

    /// Describes a normal change batch by its entries: create / delete / status change / edit of an item.
    public func label(ofBatch batchID: String) throws -> String {
        let entries = try Row.fetchAll(self, sql: "SELECT * FROM change_log WHERE batch = ? ORDER BY seq", arguments: [batchID])
        // The primary row is the first one written; later rows are follow-ups (tag assignments, link label refreshes).
        // A series rule created for a notes document is a follow-up of the notes, not a blocking change.
        let createsSeriesNotes = entries.contains { ($0["table_name"] as String) == "items" && ($0["field"] as String?) == "series_rule" }
        if !createsSeriesNotes, let rule = entries.first(where: { ($0["table_name"] as String) == "series_rules" }) {
            let r = try Row.fetchOne(self, sql: "SELECT title, blocking FROM series_rules WHERE id = ?", arguments: [rule["row_id"] as String])
            return "\(Self.blockingVerb(r?["blocking"])) “\(r?["title"] as String? ?? "series")” (series)"
        }
        if let tagLabel = try tagStructureLabel(entries) { return tagLabel }
        if let viewLabel = try viewLabel(entries) { return viewLabel }
        if let workLabel = try workLabel(entries) { return workLabel }
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
            let tag = try Row.fetchOne(self, sql: "SELECT name, page_body FROM tags WHERE id = ?", arguments: [rowID])
            let name = tag?["name"] as String? ?? "tag"
            // A bare new tag (New Subtag) vs. a description written to a tag (which may create it too).
            if own.contains(where: { ($0["op"] as String) == "insert" }), (tag?["page_body"] as String? ?? "").isEmpty {
                return "Create tag “\(name)”"
            }
            return "Edit tag page “\(name)”"
        }
        guard table == "items",
              let item = try Row.fetchOne(self, sql: "SELECT kind, title FROM items WHERE id = ?", arguments: [rowID]) else { return "change" }
        // Meeting notes (meeting-pages N4): text written or the document deleted.
        let notesWritten = own.contains { ($0["op"] as String) != "insert" && ($0["field"] as String?) == "body" }
        if (item["kind"] as String) == "event_note", notesWritten || fields.contains("series_rule") || fields.contains("deleted_at") {
            let title = item["title"] as String
            if let entry = own.first(where: { ($0["field"] as String?) == "deleted_at" }) {
                return ChangeValue.decode(entry["new_value"]).isNull ? "Restore notes “\(title)”" : "Delete notes “\(title)”"
            }
            return "Edit notes “\(title)”"
        }
        if (item["kind"] as String) == "event_note", fields.contains("blocking") || own.contains(where: { ($0["op"] as String) == "insert" }) {
            let b = try String.fetchOne(self, sql: "SELECT blocking FROM items WHERE id = ?", arguments: [rowID])
            return "\(Self.blockingVerb(b)) “\(item["title"] as String)” (this occurrence)"
        }
        if (item["kind"] as String) == "bookmark" { return Self.bookmarkLabel(own, title: item["title"]) }
        let isPage = (item["kind"] as String) == "info"
        let quoted = (isPage ? "page " : "") + "“\(item["title"] as String)”"
        if own.contains(where: { ($0["op"] as String) == "insert" }) { return "Create \(quoted)" }
        if let entry = own.first(where: { ($0["field"] as String?) == "deleted_at" }) {
            // Clearing deleted_at outside undo is a restore from the trash (trash-bin T2).
            return ChangeValue.decode(entry["new_value"]).isNull ? "Restore \(quoted)" : "Delete \(quoted)"
        }
        if fields.contains("status"), let entry = own.first(where: { ($0["field"] as String?) == "status" }),
           let status = String.fromDatabaseValue(ChangeValue.decode(entry["new_value"])) {
            let verb = ["done": "Complete", "snoozed": "Snooze", "dropped": "Drop", "open": "Reopen"][status] ?? "Status of"
            return "\(verb) \(quoted)"
        }
        if fields == ["effort"] { return "Effort of \(quoted)" }
        var changed: [String] = []
        for f in Database.fieldLabels where fields.contains(f.column) {
            let label = isPage && f.column == "body" ? "text" : f.label
            if !changed.contains(label) { changed.append(label) }
        }
        if tagsChanged { changed.append("tags") }
        return changed.isEmpty ? "Edit \(quoted)" : "Edit \(quoted) (\(changed.joined(separator: ", ")))"
    }

    /// Labels of tag colors, renames, merges and deletes (tag-colors C3, C7, C8). These batches also touch items
    /// (relabelled links, moved assignments), so the tag change has to win over the item heuristics below.
    private func tagStructureLabel(_ entries: [Row]) throws -> String? {
        let tagEntries = entries.filter { ($0["table_name"] as String) == "tags" && ($0["op"] as String) != "insert" }
        func name(_ id: String) throws -> String { try String.fetchOne(self, sql: "SELECT name FROM tags WHERE id = ?", arguments: [id]) ?? "tag" }
        func value(_ e: Row, _ column: String) -> String? { String.fromDatabaseValue(ChangeValue.decode(e[column])) }
        let tombstones = tagEntries.filter { ($0["field"] as String?) == "deleted_at" && !ChangeValue.decode($0["new_value"]).isNull }
        if let gone = tombstones.first {
            let moved = entries.contains { ($0["table_name"] as String) == "item_tags" && ($0["op"] as String) == "insert" }
                || entries.contains { ($0["table_name"] as String) == "item_tags" && ($0["field"] as String?) == "tag_id" }
            return moved ? "Merge tag “\(try name(gone["row_id"]))”" : "Delete tag “\(try name(gone["row_id"]))”"
        }
        let renames = tagEntries.filter { ($0["field"] as String?) == "name" }
        if !renames.isEmpty {
            // A renamed subtree reads as its common prefix: person/alex + person/sam -> "person" to "people".
            func common(_ names: [String]) -> String {
                let split = names.map { $0.split(separator: "/").map(String.init) }
                var prefix = split[0]
                for s in split.dropFirst() { prefix = Array(zip(prefix, s).prefix { $0.0 == $0.1 }.map(\.0)) }
                return prefix.joined(separator: "/")
            }
            let old = common(renames.compactMap { value($0, "old_value") }), new = common(renames.compactMap { value($0, "new_value") })
            return "Rename tag “\(old)” to “\(new)”"
        }
        if let colored = entries.first(where: { ($0["table_name"] as String) == "tags" && ($0["field"] as String?) == "color" }) {
            return "Color of tag “\(try name(colored["row_id"]))”"
        }
        return nil
    }

    static func blockingVerb(_ value: String?) -> String {
        switch value { case "blocks": "Blocks"; case "optional": "Optional"; case "ignore": "Ignore"; default: "Automatic" }
    }

    /// Applies the inverse of every entry of `batchID`, newest first, logging into `batch`.
    /// - Parameter only: when set, entries for other rows are skipped (a restore reverts just one item's delete).
    func revert(batch batchID: String, using batch: Batch, only: ((_ table: String, _ rowID: String) -> Bool)? = nil) throws {
        let entries = try Row.fetchAll(self, sql: "SELECT * FROM change_log WHERE batch = ? ORDER BY seq DESC", arguments: [batchID])
            .filter { only?($0["table_name"], $0["row_id"]) ?? true }
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
