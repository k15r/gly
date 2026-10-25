// Spike 2 (foundation-spikes): change-log write path (D2) + undo. Throwaway code.
import Foundation
import GRDB

public typealias Row_ = [String: DatabaseValueConvertible?]

/// JSON encoding of a single SQLite value for change_log old/new columns.
func encode(_ v: DatabaseValue) -> String? {
    switch v.storage {
    case .null: return nil
    case .int64(let i): return String(i)
    case .double(let d): return String(d)
    case .string(let s): return try! String(data: JSONEncoder().encode(s), encoding: .utf8)
    case .blob(let b): return try! String(data: JSONEncoder().encode(["blob": b.base64EncodedString()]), encoding: .utf8)
    }
}

func decode(_ s: String?) -> DatabaseValue {
    guard let s else { return .null }
    if let i = Int64(s) { return i.databaseValue }
    if let d = Double(s) { return d.databaseValue }
    if let str = try? JSONDecoder().decode(String.self, from: Data(s.utf8)) { return str.databaseValue }
    if let b = try? JSONDecoder().decode([String: String].self, from: Data(s.utf8)), let v = b["blob"], let data = Data(base64Encoded: v) {
        return data.databaseValue
    }
    return s.databaseValue
}

/// Children that are soft-deleted together with their owner, so undo restores them too.
let dependents: [String: [(table: String, column: String)]] = [
    "items": [("item_tags", "item_id"), ("property_values", "owner_id"), ("links", "from_id"), ("links", "to_id")],
    "tags": [("item_tags", "tag_id"), ("property_values", "owner_id")],
]

public struct Writer {
    public let name: String                  // "user@mac" | "agent:mail-triage"
    public init(_ name: String) { self.name = name }
}

public extension Database {
    private func log(_ batch: String, _ w: Writer, _ op: String, _ table: String, _ id: String,
                     _ field: String?, _ old: DatabaseValue, _ new: DatabaseValue, at: Date) throws {
        try execute(sql: """
            INSERT INTO change_log (at, writer, batch, op, table_name, row_id, field, old_value, new_value)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [at, w.name, batch, op, table, id, field, encode(old), encode(new)])
    }

    /// Inserts a row with D2 columns filled in. Logs one entry per non-null field.
    @discardableResult
    func insert(_ table: String, _ values: Row_, by w: Writer, batch: String = UUID().uuidString, at: Date = Date()) throws -> String {
        var row = values
        let id = (row["id"] ?? nil).map { "\($0)" } ?? UUID().uuidString
        row["id"] = id
        row["created_at"] = at
        row["modified_at"] = at
        row["modified_by"] = w.name
        let cols = row.keys.sorted()
        let sql = "INSERT INTO \(table) (\(cols.joined(separator: ","))) VALUES (\(cols.map { _ in "?" }.joined(separator: ",")))"
        try execute(sql: sql, arguments: StatementArguments(cols.map { row[$0] ?? nil }))
        for c in cols where !["created_at", "modified_at", "modified_by"].contains(c) {
            let v = (row[c] ?? nil)?.databaseValue ?? .null
            if !v.isNull { try log(batch, w, "insert", table, id, c, .null, v, at: at) }
        }
        return id
    }

    /// Updates fields; logs old/new per field that actually changed.
    func update(_ table: String, id: String, _ values: Row_, by w: Writer, batch: String = UUID().uuidString,
                at: Date = Date(), op: String = "update") throws {
        guard let current = try Row.fetchOne(self, sql: "SELECT * FROM \(table) WHERE id = ?", arguments: [id]) else {
            throw DatabaseError(message: "no \(table) row \(id)")
        }
        var changed: [(String, DatabaseValue, DatabaseValue)] = []
        for (c, v) in values {
            let old: DatabaseValue = current[c]
            let new = v?.databaseValue ?? .null
            if old != new { changed.append((c, old, new)) }
        }
        guard !changed.isEmpty else { return }
        let sets = (changed.map { "\($0.0) = ?" } + ["modified_at = ?", "modified_by = ?"]).joined(separator: ", ")
        var args: [DatabaseValueConvertible?] = changed.map { $0.2 }
        args += [at, w.name, id]
        try execute(sql: "UPDATE \(table) SET \(sets) WHERE id = ?", arguments: StatementArguments(args))
        for (c, old, new) in changed { try log(batch, w, op, table, id, c, old, new, at: at) }
    }

    /// Soft delete (tombstone) of a row and its dependents in one batch.
    func softDelete(_ table: String, id: String, by w: Writer, batch: String = UUID().uuidString, at: Date = Date()) throws {
        try update(table, id: id, ["deleted_at": at], by: w, batch: batch, at: at, op: "delete")
        for dep in dependents[table] ?? [] {
            let ids = try String.fetchAll(self, sql: "SELECT id FROM \(dep.table) WHERE \(dep.column) = ? AND deleted_at IS NULL", arguments: [id])
            for child in ids {
                try update(dep.table, id: child, ["deleted_at": at], by: w, batch: batch, at: at, op: "delete")
            }
        }
    }

    /// Undoes the most recent batch that hasn't been undone: restores old values, logs the reversal.
    /// Returns the undone batch id, or nil if there's nothing to undo.
    @discardableResult
    func undoLast(by w: Writer, at: Date = Date()) throws -> String? {
        guard let batch = try String.fetchOne(self, sql: """
            SELECT batch FROM change_log WHERE undone = 0 AND op != 'undo' ORDER BY seq DESC LIMIT 1
            """) else { return nil }
        let entries = try Row.fetchAll(self, sql: "SELECT * FROM change_log WHERE batch = ? ORDER BY seq DESC", arguments: [batch])
        let undoBatch = UUID().uuidString
        var inserted: [(String, String)] = []
        for e in entries {
            let table: String = e["table_name"], id: String = e["row_id"], op: String = e["op"]
            if op == "insert" {
                inserted.append((table, id))
            } else if let field: String = e["field"] {
                let old = decode(e["old_value"])
                let cur = try DatabaseValue.fetchOne(self, sql: "SELECT \(field) FROM \(table) WHERE id = ?", arguments: [id]) ?? .null
                try execute(sql: "UPDATE \(table) SET \(field) = ?, modified_at = ?, modified_by = ? WHERE id = ?",
                            arguments: [old, at, w.name, id])
                try log(undoBatch, w, "undo", table, id, field, cur, old, at: at)
            }
        }
        // Undoing an insert = tombstone the row (never hard delete user data).
        for (table, id) in Set(inserted.map { "\($0.0)|\($0.1)" }).map({ s -> (String, String) in
            let p = s.split(separator: "|"); return (String(p[0]), String(p[1]))
        }) {
            try execute(sql: "UPDATE \(table) SET deleted_at = ?, modified_at = ?, modified_by = ? WHERE id = ?", arguments: [at, at, w.name, id])
            try log(undoBatch, w, "undo", table, id, "deleted_at", .null, at.databaseValue, at: at)
        }
        try execute(sql: "UPDATE change_log SET undone = 1 WHERE batch = ?", arguments: [batch])
        return batch
    }
}
