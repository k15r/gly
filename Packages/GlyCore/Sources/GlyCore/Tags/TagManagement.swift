import Foundation
import GRDB

/// Renaming, merging and deleting tags (tag-colors C7, C8). Each runs inside one command batch = one undo step.
enum TagManagement {
    /// Renames `from` and its subtree to `to`. Clashing target names fail with `conflict` unless `merge` is set,
    /// in which case each clashing source is merged into the existing target.
    static func rename(from: String, to: String, merge: Bool, batch: Batch) throws -> String? {
        let db = batch.db
        let source = try TagName(from), target = try TagName(to)
        guard !(target.key.hasPrefix(source.key + "/")) else {
            throw CommandFailure(.validation, "“\(target.display)” is inside “\(source.display)”; a tag can't be moved into itself.")
        }
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, name, name_key FROM live_tags WHERE name_key = ? OR name_key LIKE ? ESCAPE '\\' ORDER BY length(name_key)
            """, arguments: [source.key, TagFilter.descendantPattern(source)])
        guard !rows.isEmpty else { throw CommandFailure(.notFound, "Tag \(source.display) not found.") }
        let sourceIDs = Set(rows.map { $0["id"] as String })
        let sourceDepth = source.key.split(separator: "/").count
        let targetSegments = target.display.split(separator: "/").map(String.init)

        // Plan: each row's new name, and the existing live tag it would collide with (outside the renamed subtree).
        var plan: [(id: String, name: String, key: String, clash: String?)] = []
        for r in rows {
            let segments = (r["name"] as String).split(separator: "/").map(String.init)
            let name = (targetSegments + segments.dropFirst(sourceDepth)).joined(separator: "/")
            let key = TagName.key(for: name)
            let clash = try String.fetchOne(db, sql: "SELECT id FROM live_tags WHERE name_key = ?", arguments: [key])
                .flatMap { sourceIDs.contains($0) ? nil : $0 }
            plan.append((r["id"], name, key, clash))
        }
        let clashes = plan.filter { $0.clash != nil }
        if !clashes.isEmpty && !merge {
            throw CommandFailure(.conflict, "Already exists: " + clashes.map(\.name).joined(separator: ", "))
        }
        for p in plan {
            if let into = p.clash { try mergeTag(p.id, into: into, batch: batch) }
            else { try batch.update("tags", id: p.id, ["name": p.name, "name_key": p.key]) }
        }
        // Links show tag names as labels: refresh them in every text linking a renamed (or merged) tag.
        for p in plan { try LinkResolver.refreshLabels(tag: p.clash ?? p.id, batch: batch) }
        return plan.first.map { $0.clash ?? $0.id }
    }

    /// Moves `source`'s assignments, description, color and links to `target`, then tombstones `source`.
    static func mergeTag(_ source: String, into target: String, batch: Batch) throws {
        let db = batch.db
        for a in try Row.fetchAll(db, sql: "SELECT id, item_id FROM live_item_tags WHERE tag_id = ?", arguments: [source]) {
            let has = try Bool.fetchOne(db, sql: "SELECT 1 FROM live_item_tags WHERE tag_id = ? AND item_id = ?",
                                        arguments: [target, a["item_id"] as String]) ?? false
            if has { try batch.softDelete("item_tags", id: a["id"]) } else { try batch.update("item_tags", id: a["id"], ["tag_id": target]) }
        }
        let s = try Row.fetchOne(db, sql: "SELECT page_body, color FROM tags WHERE id = ?", arguments: [source])
        let t = try Row.fetchOne(db, sql: "SELECT page_body, color FROM tags WHERE id = ?", arguments: [target])
        let sBody = (s?["page_body"] as String?) ?? "", tBody = (t?["page_body"] as String?) ?? ""
        var fields: Fields = [:]
        if !sBody.isEmpty { fields["page_body"] = tBody.isEmpty ? sBody : tBody + "\n\n" + sBody }
        if (t?["color"] as String?) == nil, let c = s?["color"] as String? { fields["color"] = c }
        if !fields.isEmpty { try batch.update("tags", id: target, fields) }
        // Texts linking the source now link the target.
        let sources = try Row.fetchAll(db, sql: """
            SELECT DISTINCT source_table, source_id FROM link_index WHERE target_kind = 'tag' AND target_id = ?
            """, arguments: [source.uppercased()])
        for src in sources {
            let table: String = src["source_table"], id: String = src["source_id"]
            let column = table == "tags" ? "page_body" : "body"
            guard let text = try String.fetchOne(db, sql: "SELECT \(column) FROM \(table) WHERE id = ? AND deleted_at IS NULL", arguments: [id]) else { continue }
            var rewritten = text
            for scheme in [LinkParser.scheme] + LinkParser.legacySchemes {   // old workdash:// links merge too
                rewritten = rewritten.replacingOccurrences(of: "\(scheme)://tag/\(source)", with: "\(LinkParser.scheme)://tag/\(target)",
                                                           options: .caseInsensitive)
            }
            if rewritten != text { try batch.update(table, id: id, [column: rewritten]) }
        }
        try batch.softDelete("tags", id: source)
    }

    /// Tombstones the tag and its assignments; subtags stay. Group names without a row can't be deleted.
    static func delete(_ name: String, batch: Batch) throws -> String {
        let tag = try TagName(name)
        guard let id = try String.fetchOne(batch.db, sql: "SELECT id FROM live_tags WHERE name_key = ?", arguments: [tag.key]) else {
            throw CommandFailure(.notFound, "Tag \(tag.display) not found.")
        }
        try batch.softDelete("tags", id: id)
        return id
    }
}

extension TagQueries {
    /// Live pages and tasks (any status) carrying exactly this tag (the delete confirmation's count).
    public static func usage(_ db: Database, name: String) throws -> Int {
        try Int.fetchOne(db, sql: """
            SELECT COUNT(DISTINCT i.id) FROM live_items i JOIN live_item_tags it ON it.item_id = i.id JOIN live_tags t ON t.id = it.tag_id
            WHERE t.name_key = ? AND i.kind IN ('info', 'task')
            """, arguments: [TagName.key(for: name)]) ?? 0
    }
}
