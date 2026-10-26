import Foundation
import GRDB

/// One search result (specs/search).
public struct SearchHit: Equatable, Identifiable {
    public var id: String { ref.id }
    public let ref: LinkRef
    /// Text around the match; empty when only the title matched.
    public let excerpt: String
}

/// Results grouped by kind; each group ordered by relevance (bm25 is not comparable across kinds).
public struct SearchResults: Equatable {
    public var pages: [SearchHit] = []
    public var tasks: [SearchHit] = []
    public var tags: [SearchHit] = []
    public var isEmpty: Bool { pages.isEmpty && tasks.isEmpty && tags.isEmpty }
    public var all: [SearchHit] { pages + tasks + tags }
}

public enum SearchQueries {
    /// FTS5 query for user input: every word quoted, the last one as a prefix. nil for empty input.
    public static func ftsQuery(_ input: String) -> String? {
        let words = input.split(whereSeparator: { $0.isWhitespace }).map { $0.replacingOccurrences(of: "\"", with: "") }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.enumerated().map { i, w in i == words.count - 1 ? "\"\(w)\"*" : "\"\(w)\"" }.joined(separator: " ")
    }

    public static func search(_ db: Database, _ input: String, kinds: Set<LinkRef.Kind> = [.page, .task, .tag], limit: Int = 20) throws -> SearchResults {
        guard let match = ftsQuery(input) else { return SearchResults() }
        var results = SearchResults()
        for kind in kinds {
            // Deleted rows aren't in the index (DerivedIndex); only archived tags need filtering.
            let (ftsKind, extra): (String, String)
            switch kind {
            case .page: (ftsKind, extra) = ("info", "")
            case .task: (ftsKind, extra) = ("task", "")
            case .tag: (ftsKind, extra) = ("tag", " AND owner_id NOT IN (SELECT id FROM tags WHERE archived = 1)")
            }
            let rows = try Row.fetchAll(db, sql: """
                SELECT owner_id, title, snippet(search_index, 4, '', '', '…', 12) AS excerpt
                FROM search_index
                WHERE search_index MATCH ? AND kind = ?\(extra)
                ORDER BY bm25(search_index, 0, 0, 0, 10.0, 1.0)
                LIMIT ?
                """, arguments: [match, ftsKind, limit])
            let hits = rows.map { r in
                SearchHit(ref: LinkRef(kind: kind, id: r["owner_id"], title: r["title"]),
                          excerpt: (r["excerpt"] as String? ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            }
            switch kind {
            case .page: results.pages = hits
            case .task: results.tasks = hits
            case .tag: results.tags = hits
            }
        }
        return results
    }
}
