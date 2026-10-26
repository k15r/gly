import Foundation
import GRDB

/// Values written through the change log: column name -> value (nil = NULL).
public typealias Fields = [String: DatabaseValueConvertible?]

/// One logical change (= one undo step). Every write inside it is logged with the same batch id.
public struct Batch {
    public let db: Database
    public let writer: String
    public let id: String
    public let at: Date
    /// Operation recorded for updates ("update" normally, "undo"/"redo" when replaying history).
    var updateOp = "update"

    public init(db: Database, writer: String, id: String = UUID().uuidString, at: Date = Date()) {
        self.db = db
        self.writer = writer
        self.id = id
        self.at = at
    }

    /// Children tombstoned together with their owner, so undo restores them in the same step.
    static let dependents: [String: [(table: String, column: String)]] = [
        "items": [("item_tags", "item_id")],
        "tags": [("item_tags", "tag_id")],
    ]

    private static let bookkeeping: Set = ["created_at", "modified_at", "modified_by"]

    func log(op: String, table: String, rowID: String, field: String?, old: DatabaseValue, new: DatabaseValue) throws {
        try db.execute(sql: """
            INSERT INTO change_log (at, writer, batch, op, table_name, row_id, field, old_value, new_value, redo_of)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [at, writer, id, op, table, rowID, field, ChangeValue.encode(old), ChangeValue.encode(new), redoOf])
    }

    var redoOf: String?

    /// Inserts a row, filling in id (if absent) and the sync columns. Logs every non-null field.
    @discardableResult
    public func insert(_ table: String, _ fields: Fields) throws -> String {
        var row = fields
        let rowID = (row["id"] ?? nil).map { String(describing: $0) } ?? UUID().uuidString
        row["id"] = rowID
        row["created_at"] = at
        row["modified_at"] = at
        row["modified_by"] = writer
        let columns = row.keys.sorted()
        try db.execute(
            sql: "INSERT INTO \(table) (\(columns.joined(separator: ", "))) VALUES (\(columns.map { _ in "?" }.joined(separator: ", ")))",
            arguments: StatementArguments(columns.map { row[$0] ?? nil }))
        for column in columns where !Self.bookkeeping.contains(column) {
            let value = (row[column] ?? nil)?.databaseValue ?? .null
            if !value.isNull {
                try log(op: "insert", table: table, rowID: rowID, field: column, old: .null, new: value)
            }
        }
        return rowID
    }

    /// Updates the given fields; only fields whose value actually changes are written and logged.
    /// Returns the names of the changed fields.
    @discardableResult
    public func update(_ table: String, id rowID: String, _ fields: Fields, op: String? = nil) throws -> [String] {
        guard let current = try Row.fetchOne(db, sql: "SELECT * FROM \(table) WHERE id = ?", arguments: [rowID]) else {
            throw StoreError.notFound("\(table) \(rowID)")
        }
        var changes: [(String, DatabaseValue, DatabaseValue)] = []
        for (column, value) in fields.sorted(by: { $0.key < $1.key }) {
            let old: DatabaseValue = current[column] ?? .null
            let new = value?.databaseValue ?? .null
            if old != new { changes.append((column, old, new)) }
        }
        guard !changes.isEmpty else { return [] }
        let assignments = (changes.map { "\($0.0) = ?" } + ["modified_at = ?", "modified_by = ?"]).joined(separator: ", ")
        var arguments: [DatabaseValueConvertible?] = changes.map { $0.2 }
        arguments += [at, writer, rowID]
        try db.execute(sql: "UPDATE \(table) SET \(assignments) WHERE id = ?", arguments: StatementArguments(arguments))
        for (column, old, new) in changes {
            try log(op: op ?? updateOp, table: table, rowID: rowID, field: column, old: old, new: new)
        }
        return changes.map(\.0)
    }

    /// Tombstones a row and its live dependents (never a hard delete of user data).
    public func softDelete(_ table: String, id rowID: String) throws {
        try update(table, id: rowID, ["deleted_at": at], op: "delete")
        for dependent in Self.dependents[table] ?? [] {
            let ids = try String.fetchAll(db, sql: "SELECT id FROM \(dependent.table) WHERE \(dependent.column) = ? AND deleted_at IS NULL",
                                          arguments: [rowID])
            for child in ids {
                try update(dependent.table, id: child, ["deleted_at": at], op: "delete")
            }
        }
    }
}

/// JSON encoding of single SQLite values in change_log old/new columns.
enum ChangeValue {
    private struct Wrapped: Codable { var i: Int64?; var d: Double?; var s: String?; var b: String? }

    static func encode(_ value: DatabaseValue) -> String? {
        let w: Wrapped
        switch value.storage {
        case .null: return nil
        case .int64(let i): w = Wrapped(i: i)
        case .double(let d): w = Wrapped(d: d)
        case .string(let s): w = Wrapped(s: s)
        case .blob(let data): w = Wrapped(b: data.base64EncodedString())
        }
        return String(data: try! JSONEncoder().encode(w), encoding: .utf8)
    }

    static func decode(_ text: String?) -> DatabaseValue {
        guard let text, let w = try? JSONDecoder().decode(Wrapped.self, from: Data(text.utf8)) else { return .null }
        if let i = w.i { return i.databaseValue }
        if let d = w.d { return d.databaseValue }
        if let s = w.s { return s.databaseValue }
        if let b = w.b, let data = Data(base64Encoded: b) { return data.databaseValue }
        return .null
    }
}
