import Foundation
import GRDB

/// Display names for items whose titles aren't unique (link-disambiguation K2). Computed, never stored.
public enum Disambiguation {
    public struct Item: Equatable {
        public let id: String
        public let title: String
        public let tags: [String]
        public let createdAt: Date
        public init(id: String, title: String, tags: [String], createdAt: Date) { self.id = id; self.title = title; self.tags = tags; self.createdAt = createdAt }
    }

    /// For a group of same-kind items with the same (case-folded) title: per item, the deepest tag that none of the
    /// others carries, else "created <date>". A group of one gets no qualifier.
    public static func qualifiers(_ group: [Item]) -> [String: String] {
        guard group.count > 1 else { return [:] }
        var result: [String: String] = [:]
        let date = DateFormatter(); date.dateStyle = .medium; date.timeStyle = .none
        for item in group {
            let others = Set(group.filter { $0.id != item.id }.flatMap { $0.tags.map(TagName.key(for:)) })
            let unique = item.tags.filter { !others.contains(TagName.key(for: $0)) }
                .sorted { a, b in
                    let da = a.split(separator: "/").count, dbb = b.split(separator: "/").count
                    return da != dbb ? da > dbb : a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                }
            result[item.id] = unique.first ?? "created " + date.string(from: item.createdAt)
        }
        return result
    }
}

/// A title as shown to the user, with its qualifier and tags.
public struct DisplayName: Equatable {
    public let title: String
    public let qualifier: String?
    public let tags: [String]
    public var display: String { qualifier.map { "\(title) · \($0)" } ?? title }
}

public enum DisplayNames {
    /// Display names for pages and tasks (by id). Tags get their name. Same-titled siblings are looked up per kind.
    public static func display(_ db: Database, ids: [String]) throws -> [String: DisplayName] {
        guard !ids.isEmpty else { return [:] }
        let marks = ids.map { _ in "?" }.joined(separator: ",")
        let targets = try Row.fetchAll(db, sql: "SELECT id, kind, title FROM items WHERE id IN (\(marks))", arguments: StatementArguments(ids))
        var result: [String: DisplayName] = [:]
        // Group targets by (kind, title length) so siblings are fetched once per group.
        var groups: [String: (kind: String, title: String)] = [:]
        for r in targets { groups["\(r["kind"] as String)|\(TagName.key(for: r["title"]))"] = (r["kind"], r["title"]) }
        for (_, g) in groups {
            let siblings = try Row.fetchAll(db, sql: """
                SELECT id, title, created_at FROM live_items WHERE kind = ? AND length(title) = length(?)
                """, arguments: [g.kind, g.title]).filter { TagName.key(for: $0["title"]) == TagName.key(for: g.title) }
            let tags = try TaskQueries.tagsByItem(db, ids: siblings.map { $0["id"] as String } + ids)
            let items = siblings.map { Disambiguation.Item(id: $0["id"], title: $0["title"], tags: tags[$0["id"]] ?? [], createdAt: $0["created_at"]) }
            let q = Disambiguation.qualifiers(items)
            for r in targets where (r["kind"] as String) == g.kind && TagName.key(for: r["title"]) == TagName.key(for: g.title) {
                let id: String = r["id"]
                result[id] = DisplayName(title: r["title"], qualifier: q[id], tags: tags[id] ?? [])
            }
        }
        // Tags (ids not in items): their name, never qualified.
        let missing = ids.filter { result[$0] == nil }
        if !missing.isEmpty {
            let m = missing.map { _ in "?" }.joined(separator: ",")
            for r in try Row.fetchAll(db, sql: "SELECT id, name FROM tags WHERE id IN (\(m))", arguments: StatementArguments(missing)) {
                result[r["id"]] = DisplayName(title: r["name"], qualifier: nil, tags: [])
            }
        }
        return result
    }
}
