import Foundation
import GRDB

/// New task (createTask).
public struct TaskDraft: Codable, Equatable {
    public var title: String
    public var body: String = ""
    public var priority: Priority = .none
    public var due: Due?
    public var tags: [String] = []
    public init(title: String, body: String = "", priority: Priority = .none, due: Due? = nil, tags: [String] = []) {
        self.title = title; self.body = body; self.priority = priority; self.due = due; self.tags = tags
    }
}

/// Partial update (updateTask). `nil` = unchanged. Due is replaced as a whole: `.some(nil)` clears it.
/// Tags and status may be changed in the same patch, so one editor save is one undo step.
public struct TaskPatch: Codable, Equatable {
    public var title: String?
    public var body: String?
    public var priority: Priority?
    public var due: Due??
    /// Replaces the tag set.
    public var tags: [String]?
    public var status: TaskStatus?
    /// Required with `status: .snoozed`.
    public var snoozedUntil: String?
    public init(title: String? = nil, body: String? = nil, priority: Priority? = nil, due: Due?? = nil,
                tags: [String]? = nil, status: TaskStatus? = nil, snoozedUntil: String? = nil) {
        self.title = title; self.body = body; self.priority = priority; self.due = due
        self.tags = tags; self.status = status; self.snoozedUntil = snoozedUntil
    }

    // `Due??` needs explicit coding: JSON can't tell "unchanged" from "clear" otherwise.
    private enum CodingKeys: String, CodingKey { case title, body, priority, due, clearDue, tags, status, snoozedUntil }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status)
        snoozedUntil = try c.decodeIfPresent(String.self, forKey: .snoozedUntil)
        if try c.decodeIfPresent(Bool.self, forKey: .clearDue) == true {
            due = .some(nil)
        } else if let d = try c.decodeIfPresent(Due.self, forKey: .due) {
            due = .some(d)
        } else {
            due = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(snoozedUntil, forKey: .snoozedUntil)
        switch due {
        case .none: break
        case .some(.none): try c.encode(true, forKey: .clearDue)
        case .some(.some(let d)): try c.encode(d, forKey: .due)
        }
    }
}

/// Every write the app (and later MCP) can make. Sent as JSON over XPC (design L4).
public enum Command: Codable, Equatable {
    case ping
    case createTask(TaskDraft)
    case updateTask(id: String, TaskPatch)
    case setStatus(id: String, TaskStatus, snoozedUntil: String? = nil)
    case deleteTask(id: String)
    case setTags(id: String, [String])
    case undo
    case redo
    case reconcileSnoozes(today: String)
    /// Agent state for the app (calendar access in the agent, design M5/M8). Answered by `AgentService`.
    case agentStatus
    /// Tells the agent that the shared settings changed (HTTP endpoint, design M7). No store change.
    case reloadSettings
}

public enum CommandResult: Codable, Equatable {
    case ok(CommandOK)
    case failure(CommandFailure)

    public var isOK: Bool { if case .ok = self { return true } else { return false } }
}

public struct CommandOK: Codable, Equatable {
    /// Affected item id (created/updated task), if any.
    public var id: String?
    /// For undo/redo: whether there was anything to do.
    public var changed: Bool
    public var message: String?
    public init(id: String? = nil, changed: Bool = true, message: String? = nil) { self.id = id; self.changed = changed; self.message = message }
}

public struct CommandFailure: Codable, Equatable, Error, CustomStringConvertible {
    public enum Code: String, Codable { case validation, notFound, unavailable, `internal` }
    public var code: Code
    public var message: String
    public init(_ code: Code, _ message: String) { self.code = code; self.message = message }
    public var description: String { message }
}

/// Applies commands to the store, one transaction and one change-log batch each (design L4).
public struct CommandHandler {
    let writer: DatabaseWriter

    public init(writer: DatabaseWriter) { self.writer = writer }

    public func perform(_ command: Command, writer name: String, now: Date = Date()) -> CommandResult {
        do {
            return .ok(try writer.write { db in try apply(command, db: db, writer: name, now: now) })
        } catch let failure as CommandFailure {
            return .failure(failure)
        } catch let invalid as TagName.Invalid {
            return .failure(CommandFailure(.validation, invalid.description))
        } catch StoreError.notFound(let what) {
            return .failure(CommandFailure(.notFound, "Not found: \(what)"))
        } catch {
            return .failure(CommandFailure(.internal, "\(error)"))
        }
    }

    // MARK: - Commands

    func apply(_ command: Command, db: Database, writer: String, now: Date) throws -> CommandOK {
        let batch = Batch(db: db, writer: writer, at: now)
        switch command {
        case .ping:
            return CommandOK(changed: false, message: "pong")

        case .createTask(let draft):
            let title = try Validate.title(draft.title)
            if let due = draft.due { try Validate.due(due) }
            let names = try draft.tags.map(TagName.init)
            let id = try batch.insert("items", [
                "kind": "task", "title": title, "body": draft.body, "status": TaskStatus.open.rawValue,
                "priority": draft.priority.rawValue, "due_day": draft.due?.day, "due_time": draft.due?.time,
            ])
            try replaceTags(of: id, with: names, batch: batch)
            return CommandOK(id: id)

        case .updateTask(let id, let patch):
            try requireTask(id, db)
            var fields: Fields = [:]
            if let t = patch.title { fields["title"] = try Validate.title(t) }
            if let b = patch.body { fields["body"] = b }
            if let p = patch.priority { fields["priority"] = p.rawValue }
            if let due = patch.due {
                if let due { try Validate.due(due) }
                fields.updateValue(due?.day, forKey: "due_day")
                fields.updateValue(due?.time, forKey: "due_time")
            }
            if let status = patch.status {
                try statusFields(status, snoozedUntil: patch.snoozedUntil, now: now).forEach { fields.updateValue($0.value, forKey: $0.key) }
            }
            let tagNames = try patch.tags.map { try $0.map(TagName.init) }
            var changed = try !batch.update("items", id: id, fields).isEmpty
            if let tagNames { changed = try replaceTags(of: id, with: tagNames, batch: batch) || changed }
            return CommandOK(id: id, changed: changed)

        case .setStatus(let id, let status, let snoozedUntil):
            try requireTask(id, db)
            let changed = try batch.update("items", id: id, statusFields(status, snoozedUntil: snoozedUntil, now: now))
            return CommandOK(id: id, changed: !changed.isEmpty)

        case .deleteTask(let id):
            try requireTask(id, db)
            try batch.softDelete("items", id: id)
            return CommandOK(id: id)

        case .setTags(let id, let raw):
            try requireTask(id, db)
            let changed = try replaceTags(of: id, with: try raw.map(TagName.init), batch: batch)
            return CommandOK(id: id, changed: changed)

        // The message is the step's label (titles as they are afterwards), e.g. `Edit “Plan week” (title)`.
        case .undo:
            guard let undone = try db.undo(writer: writer, at: now) else { return CommandOK(changed: false, message: "Nothing to undo.") }
            return CommandOK(message: try db.label(ofChange: undone))

        case .redo:
            guard let redone = try db.redo(writer: writer, at: now) else { return CommandOK(changed: false, message: "Nothing to redo.") }
            return CommandOK(message: try db.label(ofChange: redone))

        case .agentStatus:
            return CommandOK(changed: false, message: "calendar: unknown")

        case .reloadSettings:
            return CommandOK(changed: false)

        case .reconcileSnoozes(let today):
            try Validate.day(today)
            let due = try String.fetchAll(db, sql: """
                SELECT id FROM live_items WHERE kind = 'task' AND status = 'snoozed' AND snoozed_until <= ?
                """, arguments: [today])
            for id in due {
                var fields: Fields = ["status": TaskStatus.open.rawValue]
                fields.updateValue(nil, forKey: "snoozed_until")
                try batch.update("items", id: id, fields)
            }
            return CommandOK(changed: !due.isEmpty, message: "\(due.count) snoozed task(s) reopened")
        }
    }

    // MARK: - Helpers

    /// Item fields for a status change (status, snoozed_until, completed_at).
    private func statusFields(_ status: TaskStatus, snoozedUntil: String?, now: Date) throws -> Fields {
        var fields: Fields = ["status": status.rawValue]
        switch status {
        case .snoozed:
            guard let day = snoozedUntil else { throw CommandFailure(.validation, "Snoozing needs a date.") }
            try Validate.day(day)
            fields["snoozed_until"] = day
            fields.updateValue(nil, forKey: "completed_at")
        case .done:
            fields["completed_at"] = now
            fields.updateValue(nil, forKey: "snoozed_until")
        case .open, .dropped:
            fields.updateValue(nil, forKey: "completed_at")
            fields.updateValue(nil, forKey: "snoozed_until")
        }
        return fields
    }

    private func requireTask(_ id: String, _ db: Database) throws {
        guard try Bool.fetchOne(db, sql: "SELECT 1 FROM live_items WHERE id = ? AND kind = 'task'", arguments: [id]) == true else {
            throw CommandFailure(.notFound, "Task \(id) not found.")
        }
    }

    /// Makes the task's live tag set equal to `names`: tombstones removed assignments, inserts new ones,
    /// creates missing tags (reusing an existing tag with the same case-folded key). Returns whether anything changed.
    @discardableResult
    private func replaceTags(of itemID: String, with names: [TagName], batch: Batch) throws -> Bool {
        let db = batch.db
        let current = try Row.fetchAll(db, sql: """
            SELECT it.id AS assignment, t.name_key FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE it.item_id = ?
            """, arguments: [itemID])
        let wanted = Dictionary(names.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for row in current where wanted[row["name_key"] as String] == nil {
            try batch.softDelete("item_tags", id: row["assignment"])
            changed = true
        }
        let have = Set(current.map { $0["name_key"] as String })
        for (key, name) in wanted.sorted(by: { $0.key < $1.key }) where !have.contains(key) {
            let tagID = try String.fetchOne(db, sql: "SELECT id FROM live_tags WHERE name_key = ?", arguments: [key])
                ?? batch.insert("tags", ["name": name.display, "name_key": key])
            try batch.insert("item_tags", ["item_id": itemID, "tag_id": tagID])
            changed = true
        }
        return changed
    }
}

enum Validate {
    static func title(_ raw: String) throws -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw CommandFailure(.validation, "A task needs a title.") }
        return t
    }

    static func day(_ day: String) throws {
        guard LocalDay(day) != nil else { throw CommandFailure(.validation, "“\(day)” is not a date (YYYY-MM-DD).") }
    }

    static func due(_ due: Due) throws {
        try day(due.day)
        if let time = due.time {
            let parts = time.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m),
                  parts[0].count == 2, parts[1].count == 2 else {
                throw CommandFailure(.validation, "“\(time)” is not a time (HH:mm).")
            }
        }
    }
}
