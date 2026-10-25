// Spike 2 (foundation-spikes): FTS5 search over items and tag pages. Throwaway code.
import GRDB

public struct SearchHit: Equatable {
    public let kind: String      // "item" | "tag"
    public let id: String
    public let title: String
}

extension Database {
    /// Full-text search; tombstoned rows are excluded explicitly (views don't expose rowid). Ranked by bm25 (title weighted 5x).
    public func search(_ query: String, limit: Int = 50) throws -> [SearchHit] {
        let items = try Row.fetchAll(self, sql: """
            SELECT i.id, i.title, bm25(items_fts, 5.0, 1.0) AS rank
            FROM items_fts JOIN items i ON i.rowid = items_fts.rowid
            WHERE items_fts MATCH ? AND i.deleted_at IS NULL ORDER BY rank LIMIT ?
            """, arguments: [query, limit])
        let tags = try Row.fetchAll(self, sql: """
            SELECT t.id, t.name, bm25(tags_fts, 5.0, 1.0) AS rank
            FROM tags_fts JOIN tags t ON t.rowid = tags_fts.rowid
            WHERE tags_fts MATCH ? AND t.deleted_at IS NULL ORDER BY rank LIMIT ?
            """, arguments: [query, limit])
        let merged = items.map { (SearchHit(kind: "item", id: $0["id"], title: $0["title"]), $0["rank"] as Double) }
            + tags.map { (SearchHit(kind: "tag", id: $0["id"], title: $0["name"]), $0["rank"] as Double) }
        return merged.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }
}
