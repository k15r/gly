import Foundation
import GRDB

/// A change to one part; nil fields stay as they are, `effort: .some(nil)` removes the effort (subtasks S3).
public struct PartPatch: Codable, Equatable {
    public var title: String?
    public var effort: Effort??
    public var done: Bool?
    public init(title: String? = nil, effort: Effort?? = nil, done: Bool? = nil) { self.title = title; self.effort = effort; self.done = done }

    private enum CodingKeys: String, CodingKey { case title, effort, clearEffort, done }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        done = try c.decodeIfPresent(Bool.self, forKey: .done)
        if try c.decodeIfPresent(Bool.self, forKey: .clearEffort) == true { effort = .some(nil) }
        else if let e = try c.decodeIfPresent(Effort.self, forKey: .effort) { effort = .some(e) }
        else { effort = nil }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(done, forKey: .done)
        switch effort {
        case .none: break
        case .some(.none): try c.encode(true, forKey: .clearEffort)
        case .some(.some(let e)): try c.encode(e, forKey: .effort)
        }
    }
}

/// Parts of a task (subtasks S3): helpers for the part commands in `CommandHandler.apply`.
extension CommandHandler {
    /// Makes the task's live parts equal to `parts` in that order: given ids are kept and updated, parts without id are added,
    /// parts left out are removed (subtasks S3). False when nothing changes.
    func replaceParts(of taskID: String, with parts: [PartInput], batch: Batch) throws -> Bool {
        let existing = Set(try String.fetchAll(batch.db, sql: "SELECT id FROM live_task_parts WHERE item_id = ?", arguments: [taskID]))
        var changed = false
        var kept = Set<String>()
        for (i, part) in parts.enumerated() {
            var fields: Fields = ["title": try Validate.title(part.title), "position": Double(i + 1)]
            fields.updateValue(part.effort?.rawValue, forKey: "effort")
            if let id = part.id, existing.contains(id) {
                kept.insert(id)
                let doneAt = try Row.fetchOne(batch.db, sql: "SELECT done_at FROM task_parts WHERE id = ?", arguments: [id])?["done_at"] as Date?
                if part.done != (doneAt != nil) { fields.updateValue(part.done ? batch.at : nil, forKey: "done_at") }
                changed = !(try batch.update("task_parts", id: id, fields)).isEmpty || changed
            } else if part.id != nil {
                throw CommandFailure(.notFound, "Part \(part.id ?? "") is not a part of this task.")
            } else {
                fields["item_id"] = taskID
                if part.done { fields["done_at"] = batch.at }
                try batch.insert("task_parts", fields)
                changed = true
            }
        }
        for id in existing.subtracting(kept) { try batch.softDelete("task_parts", id: id); changed = true }
        return changed
    }

    func requirePart(_ id: String, _ db: Database) throws {
        guard try Bool.fetchOne(db, sql: """
            SELECT 1 FROM live_task_parts p JOIN live_items i ON i.id = p.item_id WHERE p.id = ?
            """, arguments: [id]) == true else { throw CommandFailure(.notFound, "Part \(id) not found.") }
    }
}
