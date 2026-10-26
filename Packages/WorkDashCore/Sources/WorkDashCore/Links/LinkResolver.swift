import Foundation
import GRDB

/// Turns typed `[[Title]]` links into canonical id links and keeps labels current (design P3).
/// A possible target of a typed link (link-disambiguation K1).
public struct LinkCandidate: Codable, Equatable, Identifiable {
    public let id: String
    public let kind: LinkRef.Kind
    public let title: String
    public let tags: [String]
    public init(id: String, kind: LinkRef.Kind, title: String, tags: [String]) { self.id = id; self.kind = kind; self.title = title; self.tags = tags }
}

/// A typed link that didn't resolve: missing (no candidates) or ambiguous (several).
public struct UnresolvedLink: Codable, Equatable {
    public let text: String
    public let candidates: [LinkCandidate]
    public init(text: String, candidates: [LinkCandidate]) { self.text = text; self.candidates = candidates }
}

public enum LinkResolver {
    /// Splits an optional `page:`, `task:` or `tag:` prefix off a typed link (link-disambiguation K1).
    static func parse(_ typed: String) -> (kinds: Set<LinkRef.Kind>, body: String) {
        let t = typed.trimmingCharacters(in: .whitespaces)
        for (prefix, kind) in [("page:", LinkRef.Kind.page), ("task:", .task), ("tag:", .tag)] where t.lowercased().hasPrefix(prefix) {
            return ([kind], String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
        }
        return ([.page, .task, .tag], t)
    }

    /// Everything a typed `[[…]]` could mean: exact title/name matches of the allowed kinds, else (with `/`)
    /// pages/tasks titled like the last segment that carry the tag before it or a tag below it.
    public static func candidates(_ db: Database, typed: String) throws -> [LinkCandidate] {
        let (kinds, body) = parse(typed)
        let key = TagName.key(for: body)
        guard !key.isEmpty else { return [] }
        var found = try items(db, titleKey: key, title: body, kinds: kinds, tagKey: nil)
        if kinds.contains(.tag) {
            found += try Row.fetchAll(db, sql: "SELECT id, name FROM live_tags WHERE name_key = ?", arguments: [key])
                .map { LinkCandidate(id: $0["id"], kind: .tag, title: $0["name"], tags: []) }
        }
        if found.isEmpty, let slash = body.lastIndex(of: "/") {
            let tagPath = String(body[..<slash]).trimmingCharacters(in: .whitespaces)
            let title = String(body[body.index(after: slash)...]).trimmingCharacters(in: .whitespaces)
            if !tagPath.isEmpty, !title.isEmpty {
                found = try items(db, titleKey: TagName.key(for: title), title: title, kinds: kinds.subtracting([.tag]), tagKey: TagName.key(for: tagPath))
            }
        }
        return found
    }

    static func items(_ db: Database, titleKey: String, title: String, kinds: Set<LinkRef.Kind>, tagKey: String?) throws -> [LinkCandidate] {
        let itemKinds = kinds.compactMap { k -> String? in k == .page ? "info" : (k == .task ? "task" : nil) }
        guard !itemKinds.isEmpty else { return [] }
        var sql = """
            SELECT id, kind, title FROM live_items
            WHERE kind IN (\(itemKinds.map { "'\($0)'" }.joined(separator: ","))) AND length(title) = length(?)
            """
        var args: [DatabaseValueConvertible] = [title]
        if let tagKey {
            sql += """
                 AND id IN (SELECT it.item_id FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id
                            WHERE t.name_key = ? OR t.name_key LIKE ? ESCAPE '\\')
                """
            args += [tagKey, TagFilter.escapeLike(tagKey) + "/%"]
        }
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).filter { TagName.key(for: $0["title"]) == titleKey }
        let tags = try TaskQueries.tagsByItem(db, ids: rows.map { $0["id"] as String })
        return rows.map { r in
            LinkCandidate(id: r["id"], kind: (r["kind"] as String) == "info" ? .page : .task, title: r["title"], tags: tags[r["id"]] ?? [])
        }
    }

    /// Resolves unique `[[…]]` links (prefixes and tag paths included) and refreshes labels of canonical links to live targets.
    /// Returns the new text and the links that stayed unresolved, with their candidates when several items matched.
    public static func resolve(_ text: String, db: Database) throws -> (text: String, unresolved: [UnresolvedLink]) {
        let ns = NSMutableString(string: text)
        var unresolved: [UnresolvedLink] = []
        for link in LinkParser.links(in: text).reversed() {
            switch link.target {
            case .missing(let typed):
                let found = try candidates(db, typed: typed)
                if found.count == 1, let c = found.first {
                    ns.replaceCharacters(in: link.range, with: c.kind == .tag
                                         ? LinkParser.canonical(label: c.title, tag: c.id)
                                         : LinkParser.canonical(label: c.title, item: c.id))
                } else {
                    unresolved.insert(UnresolvedLink(text: typed, candidates: found), at: 0)
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
        // Exact typed titles plus forms ending in the title (`tag/path/Title`, `page:Title`).
        let sources = try Row.fetchAll(batch.db, sql: """
            SELECT DISTINCT source_table, source_id FROM link_index
            WHERE target_kind = 'missing' AND (missing_key = ? OR missing_key LIKE ? ESCAPE '\\' OR missing_key LIKE ? ESCAPE '\\')
            """, arguments: [key, "%/" + TagFilter.escapeLike(key), "%:" + TagFilter.escapeLike(key)])
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
