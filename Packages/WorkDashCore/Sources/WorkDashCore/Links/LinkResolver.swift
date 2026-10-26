import Foundation
import GRDB

/// Turns typed `[[Title]]` links into canonical id links and keeps labels current (design P3).
public enum LinkResolver {
    public struct Candidate: Equatable {
        public enum Kind: String { case item, tag }
        public let kind: Kind
        public let id: String
        public let label: String
    }

    /// Live pages/tasks and tags whose title/name equals `title` (case-folded like tag keys).
    public static func candidates(_ db: Database, title: String) throws -> [Candidate] {
        let key = TagName.key(for: title.trimmingCharacters(in: .whitespaces))
        guard !key.isEmpty else { return [] }
        // Prefilter by length (case folding rarely changes it), compare exactly in Swift.
        let items = try Row.fetchAll(db, sql: """
            SELECT id, title FROM items WHERE deleted_at IS NULL AND kind IN ('info', 'task') AND length(title) = length(?)
            """, arguments: [title.trimmingCharacters(in: .whitespaces)])
            .filter { TagName.key(for: $0["title"]) == key }
            .map { Candidate(kind: .item, id: $0["id"], label: $0["title"]) }
        let tags = try Row.fetchAll(db, sql: "SELECT id, name FROM tags WHERE deleted_at IS NULL AND name_key = ?", arguments: [key])
            .map { Candidate(kind: .tag, id: $0["id"], label: $0["name"]) }
        return items + tags
    }

    /// Resolves unique `[[Title]]` links and refreshes labels of canonical links to live targets.
    /// Returns the new text and the titles that stayed unresolved (missing or ambiguous).
    public static func resolve(_ text: String, db: Database) throws -> (text: String, unresolved: [String]) {
        let ns = NSMutableString(string: text)
        var unresolved: [String] = []
        for link in LinkParser.links(in: text).reversed() {
            switch link.target {
            case .missing(let title):
                let found = try candidates(db, title: title)
                if found.count == 1, let c = found.first {
                    ns.replaceCharacters(in: link.range, with: c.kind == .item
                                         ? LinkParser.canonical(label: c.label, item: c.id)
                                         : LinkParser.canonical(label: c.label, tag: c.id))
                } else {
                    unresolved.insert(title, at: 0)
                }
            case .item(let id):
                if let title = try String.fetchOne(db, sql: "SELECT title FROM items WHERE id = ? AND deleted_at IS NULL", arguments: [id]),
                   LinkParser.escapeLabel(title) != link.label {
                    ns.replaceCharacters(in: link.range, with: LinkParser.canonical(label: title, item: id))
                }
            case .tag(let id):
                if let name = try String.fetchOne(db, sql: "SELECT name FROM tags WHERE id = ? AND deleted_at IS NULL", arguments: [id]),
                   LinkParser.escapeLabel(name) != link.label {
                    ns.replaceCharacters(in: link.range, with: LinkParser.canonical(label: name, tag: id))
                }
            }
        }
        return (ns as String, unresolved)
    }

    /// Re-resolves the texts of live sources that link to `[[title]]` as missing (after a page got that title).
    static func resolveMissing(title: String, batch: Batch) throws {
        let key = TagName.key(for: title)
        let sources = try Row.fetchAll(batch.db, sql: "SELECT DISTINCT source_table, source_id FROM link_index WHERE target_kind = 'missing' AND missing_key = ?",
                                       arguments: [key])
        try rewrite(sources, batch: batch)
    }

    /// Refreshes labels in live sources that link to the item `id` (after a rename).
    static func refreshLabels(item id: String, batch: Batch) throws {
        let sources = try Row.fetchAll(batch.db, sql: "SELECT DISTINCT source_table, source_id FROM link_index WHERE target_kind = 'item' AND target_id = ?",
                                       arguments: [id.uppercased()])
        try rewrite(sources, batch: batch)
    }

    private static func rewrite(_ sources: [Row], batch: Batch) throws {
        for s in sources {
            let table: String = s["source_table"], id: String = s["source_id"]
            let column = table == "tags" ? "page_body" : "body"
            guard let text = try String.fetchOne(batch.db, sql: "SELECT \(column) FROM \(table) WHERE id = ? AND deleted_at IS NULL", arguments: [id]) else { continue }
            let resolved = try resolve(text, db: batch.db).text
            if resolved != text { try batch.update(table, id: id, [column: resolved]) }
        }
    }
}
