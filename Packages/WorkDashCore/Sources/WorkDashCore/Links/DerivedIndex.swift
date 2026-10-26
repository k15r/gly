import Foundation
import GRDB

/// Local-only indexes derived from text (design P2): `link_index` and the FTS5 `search_index`.
/// Never synced or change-logged; refreshed by `Batch` on every write of a watched column and rebuildable at any time.
public enum DerivedIndex {
    /// Columns whose change requires a refresh, per table.
    static let watched: [String: Set<String>] = [
        "items": ["title", "body", "deleted_at", "kind"],
        "tags": ["name", "page_body", "deleted_at"],
    ]

    static func needsRefresh(_ table: String, columns: some Sequence<String>) -> Bool {
        guard let w = watched[table] else { return false }
        return columns.contains { w.contains($0) }
    }

    /// Stable FTS rowid for an owner id (UUIDs are random; the first 8 bytes are as unique as needed).
    static func rowid(for id: String) -> Int64 {
        if let uuid = UUID(uuidString: id) {
            let b = uuid.uuid
            let bytes: [UInt8] = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7]
            return bytes.reduce(Int64(0)) { ($0 << 8) | Int64($1) } & Int64.max
        }
        var h: UInt64 = 1469598103934665603         // FNV-1a for non-UUID ids (tests)
        for c in id.utf8 { h = (h ^ UInt64(c)) &* 1099511628211 }
        return Int64(bitPattern: h) & Int64.max
    }

    /// Re-derives the index rows of one item or tag (deleted rows are kept; queries join live rows).
    public static func refresh(_ db: Database, table: String, id: String) throws {
        let row: Row?
        let kind: String, title: String, text: String
        switch table {
        case "items":
            row = try Row.fetchOne(db, sql: "SELECT kind, title, body FROM items WHERE id = ?", arguments: [id])
            guard let row else { return }
            (kind, title, text) = (row["kind"], row["title"], row["body"])
        case "tags":
            row = try Row.fetchOne(db, sql: "SELECT name, page_body FROM tags WHERE id = ?", arguments: [id])
            guard let row else { return }
            (kind, title, text) = ("tag", row["name"], row["page_body"])
        default:
            return
        }
        try db.execute(sql: "DELETE FROM link_index WHERE source_table = ? AND source_id = ?", arguments: [table, id])
        for link in LinkParser.links(in: text) {
            let (targetKind, targetID, missingTitle): (String, String?, String?)
            switch link.target {
            case .item(let t): (targetKind, targetID, missingTitle) = ("item", t, nil)
            case .tag(let t): (targetKind, targetID, missingTitle) = ("tag", t, nil)
            case .missing(let t): (targetKind, targetID, missingTitle) = ("missing", nil, t)
            }
            try db.execute(sql: """
                INSERT INTO link_index (source_table, source_id, target_kind, target_id, missing_title, missing_key, range_location, range_length)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [table, id, targetKind, targetID, missingTitle, missingTitle.map(TagName.key(for:)),
                                 link.range.location, link.range.length])
        }
        let rowid = rowid(for: id)
        try db.execute(sql: "DELETE FROM search_index WHERE rowid = ?", arguments: [rowid])
        try db.execute(sql: "INSERT INTO search_index (rowid, owner_table, owner_id, kind, title, text) VALUES (?, ?, ?, ?, ?, ?)",
                       arguments: [rowid, table, id, kind, title, LinkParser.plainText(text)])
    }

    /// Rebuilds both indexes from scratch (migration backfill; later after sync).
    public static func rebuild(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM link_index")
        try db.execute(sql: "DELETE FROM search_index")
        for id in try String.fetchAll(db, sql: "SELECT id FROM items") { try refresh(db, table: "items", id: id) }
        for id in try String.fetchAll(db, sql: "SELECT id FROM tags") { try refresh(db, table: "tags", id: id) }
    }
}
