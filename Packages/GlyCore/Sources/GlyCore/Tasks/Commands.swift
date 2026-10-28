import Foundation
import GRDB

/// New task (createTask).
public struct TaskDraft: Codable, Equatable {
    public var title: String
    public var body: String = ""
    public var priority: Priority = .none
    public var due: Due?
    public var tags: [String] = []
    public var effort: Effort?
    public init(title: String, body: String = "", priority: Priority = .none, due: Due? = nil, tags: [String] = [], effort: Effort? = nil) {
        self.title = title; self.body = body; self.priority = priority; self.due = due; self.tags = tags; self.effort = effort
    }
}

/// New info page (createPage).
public struct PageDraft: Codable, Equatable {
    public var title: String
    public var body: String
    public var tags: [String]
    public init(title: String, body: String = "", tags: [String] = []) { self.title = title; self.body = body; self.tags = tags }
}

/// Partial page update (updatePage). `nil` = unchanged. `session` coalesces saves of one edit session (design P6).
public struct PagePatch: Codable, Equatable {
    public var title: String?
    public var body: String?
    public var tags: [String]?
    public var session: String?
    public init(title: String? = nil, body: String? = nil, tags: [String]? = nil, session: String? = nil) {
        self.title = title; self.body = body; self.tags = tags; self.session = session
    }
}

/// Partial update (updateTask). `nil` = unchanged. Due is replaced as a whole: `.some(nil)` clears it.
/// Tags and status may be changed in the same patch, so one editor save is one undo step.
/// A remaining effort to set (task-progress P2): `effortMinutes` is the task's effort as the caller's sizes define it.
public struct RemainingChange: Codable, Equatable {
    public var minutes: Int
    public var effortMinutes: Int
    public var day: String
    public init(minutes: Int, effortMinutes: Int, day: String) { self.minutes = minutes; self.effortMinutes = effortMinutes; self.day = day }
}

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
    /// Edit session of the notes field (design P6).
    public var session: String?
    /// `.some(nil)` removes the effort.
    public var effort: Effort??
    /// Sets the remaining effort in the same step (agents, task-progress P6).
    public var remaining: RemainingChange?
    public init(title: String? = nil, body: String? = nil, priority: Priority? = nil, due: Due?? = nil,
                tags: [String]? = nil, status: TaskStatus? = nil, snoozedUntil: String? = nil, session: String? = nil,
                effort: Effort?? = nil) {
        self.title = title; self.body = body; self.priority = priority; self.due = due
        self.tags = tags; self.status = status; self.snoozedUntil = snoozedUntil; self.session = session; self.effort = effort
    }

    // `Due??` / `Effort??` need explicit coding: JSON can't tell "unchanged" from "clear" otherwise.
    private enum CodingKeys: String, CodingKey {
        case title, body, priority, due, clearDue, tags, status, snoozedUntil, session, effort, clearEffort, remaining
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status)
        snoozedUntil = try c.decodeIfPresent(String.self, forKey: .snoozedUntil)
        session = try c.decodeIfPresent(String.self, forKey: .session)
        remaining = try c.decodeIfPresent(RemainingChange.self, forKey: .remaining)
        if try c.decodeIfPresent(Bool.self, forKey: .clearEffort) == true { effort = .some(nil) }
        else if let e = try c.decodeIfPresent(Effort.self, forKey: .effort) { effort = .some(e) }
        else { effort = nil }
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
        try c.encodeIfPresent(session, forKey: .session)
        try c.encodeIfPresent(remaining, forKey: .remaining)
        switch effort {
        case .none: break
        case .some(.none): try c.encode(true, forKey: .clearEffort)
        case .some(.some(let e)): try c.encode(e, forKey: .effort)
        }
        switch due {
        case .none: break
        case .some(.none): try c.encode(true, forKey: .clearDue)
        case .some(.some(let d)): try c.encode(d, forKey: .due)
        }
    }
}

/// The meeting a notes command addresses: the appointment as last seen, and whether it repeats (meeting-pages N4).
public struct MeetingTarget: Codable, Equatable {
    public var snapshot: AppointmentSnapshot
    public var recurring: Bool
    public init(snapshot: AppointmentSnapshot, recurring: Bool) { self.snapshot = snapshot; self.recurring = recurring }
    public init(_ a: Appointment) { self.init(snapshot: AppointmentSnapshot(a), recurring: a.isRecurring) }
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
    /// Records minutes of work on a task for a day (task-progress P2).
    case recordWork(id: String, day: String, minutes: Int, kind: WorkKind)
    /// Sets the remaining effort: records the difference to the current remaining as an adjustment of `day`.
    /// `effortMinutes` is the task's effort in minutes as the caller's sizes define it.
    case setRemaining(id: String, minutes: Int, effortMinutes: Int, day: String)
    /// Removes all recorded work of a task (back to the full effort); undo restores it.
    case resetRemaining(id: String)
    /// Takes back "done for today": removes the day's `part` rows.
    case undoTodaysPart(id: String, day: String)
    /// Agent state for the app (calendar access in the agent, design M5/M8). Answered by `AgentService`.
    case agentStatus
    /// Tells the agent that the shared settings changed (HTTP endpoint, design M7). No store change.
    case reloadSettings
    case createPage(PageDraft)
    case updatePage(id: String, PagePatch)
    case deletePage(id: String)
    /// Replaces a tag's page description; creates the tag if it doesn't exist (e.g. a group node like `person`).
    case updateTagPage(name: String, body: String, session: String? = nil)
    /// Brings a deleted page or task back as it was when deleted, as a change of the caller (trash-bin T2).
    case restore(id: String)
    /// Erases all data for good: items, tags, overrides, the trash and the whole history (Settings → Data). Not undoable.
    case eraseAllData
    /// Replaces a meeting's notes (series document for recurring meetings); rows are created on first text (meeting-pages N4).
    case saveMeetingNotes(MeetingTarget, body: String, tags: [String]? = nil, session: String? = nil)
    /// Adds markdown to the dated section of `day` (YYYY-MM-DD) in the meeting's notes (agents).
    case appendMeetingNotes(MeetingTarget, day: String, markdown: String)
    /// Changes existing meeting notes by id (the meeting page opened from search, tags or backlinks).
    case updateMeetingNotes(id: String, body: String?, tags: [String]? = nil, session: String? = nil)
    /// Deletes a meeting's notes (Trash); a one-off row that also carries a blocking override is only emptied.
    case deleteMeetingNotes(id: String)
    /// Sets or clears (nil) a tag's own color; creates the tag row for a group name (tag-colors C3).
    case setTagColor(name: String, color: TagColor?)
    /// Renames a tag and its subtree; an existing target name fails with `conflict` unless `merge` (tag-colors C7).
    case renameTag(from: String, to: String, merge: Bool = false)
    /// Deletes a tag (its assignments too; subtags stay) (tag-colors C8).
    case deleteTag(name: String)
    /// Creates an (empty) tag, e.g. a new subtag; an existing tag is returned unchanged (case-insensitive).
    case createTag(name: String)
    /// Blocking override for one occurrence or a whole series; nil = automatic (specs/appointment-annotations).
    case setBlocking(AppointmentSnapshot, scope: BlockingScope, value: BlockingOverride?)
    /// Re-attaches annotations in `[from, to)` to the calendar's current appointments (agent, design Q4).
    case reconcileAnnotations(from: Date, to: Date, appointments: [ObservedAppointment])
    /// The user picked the appointment an ambiguous annotation belongs to.
    case resolveAnnotation(id: String, to: AppointmentSnapshot)
    /// Pins a typed `[[typed]]` link in an item's or tag page's text to a chosen target (link-disambiguation K5).
    case resolveLink(sourceTable: String, sourceID: String, typed: String, target: LinkCandidate)
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
    /// `[[…]]` links that stayed unresolved in the written text (their typed text).
    public var unresolved: [String]?
    /// The same, with candidates for ambiguous ones.
    public var unresolvedLinks: [UnresolvedLink]?
    public init(id: String? = nil, changed: Bool = true, message: String? = nil, unresolved: [UnresolvedLink]? = nil) {
        self.id = id; self.changed = changed; self.message = message
        self.unresolvedLinks = unresolved; self.unresolved = unresolved?.map(\.text)
    }
}

public struct CommandFailure: Codable, Equatable, Error, CustomStringConvertible {
    public enum Code: String, Codable { case validation, notFound, unavailable, `internal`, conflict }
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
            if command == .eraseAllData {
                // Outside the change log by design, then compacted so the erased data doesn't linger in free pages.
                try writer.write { db in try Schema.eraseAllData(db) }
                try? writer.vacuum()        // best effort: the erase itself is done and committed

                return .ok(CommandOK(message: "All data erased."))
            }
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

    // One switch over every command is the point of this function (each case is short); not split for the linter.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func apply(_ command: Command, db: Database, writer: String, now: Date) throws -> CommandOK {
        var batch = Batch(db: db, writer: writer, id: try coalescedBatch(command, db: db, writer: writer) ?? UUID().uuidString, at: now)
        batch.session = Self.session(of: command)
        switch command {
        case .ping:
            return CommandOK(changed: false, message: "pong")

        case .createTask(let draft):
            let title = try Validate.title(draft.title)
            if let due = draft.due { try Validate.due(due) }
            let names = try draft.tags.map(TagName.init)
            let (body, unresolved) = try LinkResolver.resolve(draft.body, db: db)
            let id = try batch.insert("items", [
                "kind": "task", "title": title, "body": body, "status": TaskStatus.open.rawValue,
                "priority": draft.priority.rawValue, "due_day": draft.due?.day, "due_time": draft.due?.time,
                "effort": draft.effort?.rawValue,
            ])
            try replaceTags(of: id, with: names, batch: batch)
            // Like a new page: `[[title]]` (or `[[tag/path/title]]`) elsewhere now points to the task (design P3).
            try LinkResolver.resolveMissing(title: title, batch: batch)
            return CommandOK(id: id, unresolved: unresolved)

        case .updateTask(let id, let patch):
            try requireTask(id, db)
            var fields: Fields = [:]
            var unresolved: [UnresolvedLink]?
            if let t = patch.title { fields["title"] = try Validate.title(t) }
            if let b = patch.body { let r = try LinkResolver.resolve(b, db: db); fields["body"] = r.text; unresolved = r.unresolved }
            if let p = patch.priority { fields["priority"] = p.rawValue }
            if let effort = patch.effort { fields.updateValue(effort?.rawValue, forKey: "effort") }
            if let due = patch.due {
                if let due { try Validate.due(due) }
                fields.updateValue(due?.day, forKey: "due_day")
                fields.updateValue(due?.time, forKey: "due_time")
            }
            if let status = patch.status {
                try statusFields(status, snoozedUntil: patch.snoozedUntil, now: now).forEach { fields.updateValue($0.value, forKey: $0.key) }
            }
            let tagNames = try patch.tags.map { try $0.map(TagName.init) }
            let written = try batch.update("items", id: id, fields)
            var changed = !written.isEmpty
            if let tagNames { changed = try replaceTags(of: id, with: tagNames, batch: batch) || changed }
            if let remaining = patch.remaining { changed = try setRemaining(id, remaining, batch: batch) || changed }
            if written.contains("title"), let title = patch.title?.trimmingCharacters(in: .whitespacesAndNewlines) {
                try LinkResolver.refreshLabels(item: id, batch: batch)
                try LinkResolver.resolveMissing(title: title, batch: batch)
            }
            return CommandOK(id: id, changed: changed, unresolved: unresolved)

        case .createPage(let draft):
            let title = try Validate.title(draft.title)
            let names = try draft.tags.map(TagName.init)
            let (body, unresolved) = try LinkResolver.resolve(draft.body, db: db)
            let id = try batch.insert("items", ["kind": "info", "title": title, "body": body])
            try replaceTags(of: id, with: names, batch: batch)
            // Every `[[title]]` elsewhere now points to the new page, in the same undo step (design P3).
            try LinkResolver.resolveMissing(title: title, batch: batch)
            return CommandOK(id: id, unresolved: unresolved)

        case .updatePage(let id, let patch):
            try requirePage(id, db)
            var fields: Fields = [:]
            var unresolved: [UnresolvedLink]?
            if let t = patch.title { fields["title"] = try Validate.title(t) }
            if let b = patch.body { let r = try LinkResolver.resolve(b, db: db); fields["body"] = r.text; unresolved = r.unresolved }
            let tagNames = try patch.tags.map { try $0.map(TagName.init) }
            let written = try batch.update("items", id: id, fields)
            var changed = !written.isEmpty
            if let tagNames { changed = try replaceTags(of: id, with: tagNames, batch: batch) || changed }
            if written.contains("title"), let title = patch.title?.trimmingCharacters(in: .whitespacesAndNewlines) {
                try LinkResolver.refreshLabels(item: id, batch: batch)
                try LinkResolver.resolveMissing(title: title, batch: batch)
            }
            return CommandOK(id: id, changed: changed, unresolved: unresolved)

        case .deletePage(let id):
            try requirePage(id, db)
            try batch.softDelete("items", id: id)
            return CommandOK(id: id)

        case .updateTagPage(let name, let body, _):
            let tag = try TagName(name)
            let (text, unresolved) = try LinkResolver.resolve(body, db: db)
            if let tagID = try String.fetchOne(db, sql: "SELECT id FROM live_tags WHERE name_key = ?", arguments: [tag.key]) {
                let changed = try batch.update("tags", id: tagID, ["page_body": text])
                return CommandOK(id: tagID, changed: !changed.isEmpty, unresolved: unresolved)
            }
            let tagID = try batch.insert("tags", ["name": tag.display, "name_key": tag.key, "page_body": text])
            return CommandOK(id: tagID, unresolved: unresolved)

        case .eraseAllData:
            try Schema.eraseAllData(db)                // normally handled in perform (with VACUUM); kept for completeness
            return CommandOK(message: "All data erased.")

        case .restore(let id):
            guard let entry = try TrashQueries.entry(db, id: id) else {
                throw CommandFailure(.notFound, "\(id) is not in the trash.")
            }
            if let deleteBatch = entry.batch {
                // Revert only this item and its tag assignments from the delete batch (assignments removed earlier stay removed).
                let assignments = Set(try String.fetchAll(db, sql: "SELECT id FROM item_tags WHERE item_id = ?", arguments: [id]))
                try db.revert(batch: deleteBatch, using: batch) { table, row in
                    (table == "items" && row == id) || (table == "item_tags" && assignments.contains(row))
                }
            } else {
                try batch.update("items", id: id, ["deleted_at": nil])    // deleted without history: the item only
            }
            return CommandOK(id: id)

        case .saveMeetingNotes(let target, let body, let tags, _):
            return try saveMeetingNotes(target, body: body, tags: tags, batch: batch)

        case .appendMeetingNotes(let target, let dayString, let markdown):
            guard let day = LocalDay(dayString) else { throw CommandFailure(.validation, "day must be YYYY-MM-DD.") }
            let current = try Self.meetingNotesRow(target, db: db).flatMap {
                try String.fetchOne(db, sql: "SELECT body FROM items WHERE id = ?", arguments: [$0])
            } ?? ""
            let body = NotesSections.insert(markdown, for: day, into: current, today: LocalDay(date: now))
            return try saveMeetingNotes(target, body: body, tags: nil, batch: batch)

        case .updateMeetingNotes(let id, let body, let tags, _):
            guard try Bool.fetchOne(db, sql: "SELECT 1 FROM live_items WHERE id = ? AND kind = 'event_note'", arguments: [id]) == true else {
                throw CommandFailure(.notFound, "Meeting notes \(id) not found.")
            }
            var changed = false
            var unresolved: [UnresolvedLink]?
            if let body {
                let r = try LinkResolver.resolve(body, db: db); unresolved = r.unresolved
                changed = !(try batch.update("items", id: id, ["body": r.text])).isEmpty
            }
            if let tags { changed = try replaceTags(of: id, with: try tags.map(TagName.init), batch: batch) || changed }
            return CommandOK(id: id, changed: changed, unresolved: unresolved)

        case .deleteMeetingNotes(let id):
            guard let row = try Row.fetchOne(db, sql: "SELECT event_key, blocking FROM live_items WHERE id = ? AND kind = 'event_note'", arguments: [id]) else {
                throw CommandFailure(.notFound, "Meeting notes \(id) not found.")
            }
            if (row["event_key"] as String?) != nil, (row["blocking"] as String?) != nil {
                // The row also carries a blocking override for this meeting: keep it, empty the notes.
                try batch.update("items", id: id, ["body": ""])
                try replaceTags(of: id, with: [], batch: batch)
            } else {
                try batch.softDelete("items", id: id)
            }
            return CommandOK(id: id)

        case .setTagColor(let name, let color):
            let tag = try TagName(name)
            let tagID = try String.fetchOne(db, sql: "SELECT id FROM live_tags WHERE name_key = ?", arguments: [tag.key])
                ?? batch.insert("tags", ["name": tag.display, "name_key": tag.key, "page_body": ""])
            let changed = try batch.update("tags", id: tagID, ["color": color?.rawValue])
            return CommandOK(id: tagID, changed: !changed.isEmpty)

        case .renameTag(let from, let to, let merge):
            return CommandOK(id: try TagManagement.rename(from: from, to: to, merge: merge, batch: batch))

        case .deleteTag(let name):
            return CommandOK(id: try TagManagement.delete(name, batch: batch))

        case .createTag(let name):
            let tag = try TagName(name)
            if let tagID = try String.fetchOne(db, sql: "SELECT id FROM live_tags WHERE name_key = ?", arguments: [tag.key]) {
                return CommandOK(id: tagID, changed: false)
            }
            return CommandOK(id: try batch.insert("tags", ["name": tag.display, "name_key": tag.key, "page_body": ""]))

        case .setStatus(let id, let status, let snoozedUntil):
            try requireTask(id, db)
            let changed = try batch.update("items", id: id, statusFields(status, snoozedUntil: snoozedUntil, now: now))
            return CommandOK(id: id, changed: !changed.isEmpty)

        case .deleteTask(let id):
            try requireTask(id, db)
            try batch.softDelete("items", id: id)
            return CommandOK(id: id)

        case .recordWork(let id, let day, let minutes, let kind):
            try requireTask(id, db)
            try Validate.day(day)
            guard minutes != 0 else { return CommandOK(id: id, changed: false) }
            try batch.insert("task_work", ["item_id": id, "day": day, "minutes": minutes, "kind": kind.rawValue])
            return CommandOK(id: id)

        case .setRemaining(let id, let minutes, let effortMinutes, let day):
            try requireTask(id, db)
            let changed = try setRemaining(id, RemainingChange(minutes: minutes, effortMinutes: effortMinutes, day: day), batch: batch)
            return CommandOK(id: id, changed: changed)

        case .resetRemaining(let id):
            try requireTask(id, db)
            let rows = try String.fetchAll(db, sql: "SELECT id FROM live_task_work WHERE item_id = ?", arguments: [id])
            for row in rows { try batch.softDelete("task_work", id: row) }
            return CommandOK(id: id, changed: !rows.isEmpty)

        case .undoTodaysPart(let id, let day):
            try requireTask(id, db)
            let rows = try String.fetchAll(db, sql: "SELECT id FROM live_task_work WHERE item_id = ? AND day = ? AND kind = 'part'",
                                           arguments: [id, day])
            for row in rows { try batch.softDelete("task_work", id: row) }
            return CommandOK(id: id, changed: !rows.isEmpty)

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

        case .setBlocking(let snap, let scope, let value):
            switch scope {
            case .occurrence:
                if let id = try String.fetchOne(db, sql: "SELECT id FROM live_items WHERE kind = 'event_note' AND event_key = ?", arguments: [snap.key]) {
                    let changed = try batch.update("items", id: id, Self.blockingFields(value))
                    return CommandOK(id: id, changed: !changed.isEmpty)
                }
                guard let value else { return CommandOK(changed: false) }
                let id = try batch.insert("items", [
                    "kind": "event_note", "title": snap.title.isEmpty ? "Appointment" : snap.title, "body": "",
                    "event_key": snap.key, "event_series": snap.seriesKey, "event_calendar": snap.calendarID,
                    "event_start": snap.start, "event_end": snap.end, "event_organizer": snap.organizer,
                    "event_state": "active", "blocking": value.rawValue,
                ])
                return CommandOK(id: id)
            case .series:
                let rules = try AnnotationQueries.seriesRules(db).filter { $0.calendarID == snap.calendarID && $0.baseIDs.contains(snap.baseID) }
                if let rule = rules.first {
                    let changed = try batch.update("series_rules", id: rule.id, Self.blockingFields(value))
                    return CommandOK(id: rule.id, changed: !changed.isEmpty)
                }
                guard let value else { return CommandOK(changed: false) }
                let id = try batch.insert("series_rules", [
                    "calendar_id": snap.calendarID, "title": snap.title, "organizer": snap.organizer,
                    "base_ids": AnnotationQueries.encodeIDs([snap.baseID]), "blocking": value.rawValue,
                ])
                return CommandOK(id: id)
            }

        case .reconcileAnnotations(let from, let to, let appointments):
            let annotations = try AnnotationQueries.annotations(db, from: from, to: to)
            let changes = AnnotationMatcher.reconcile(annotations: annotations, appointments: appointments,
                                                      rules: try AnnotationQueries.seriesRules(db))
            for change in changes {
                switch change {
                case .update(let id, let o):
                    try batch.update("items", id: id, Self.snapshotFields(o.snapshot, state: o.isCancelled ? "cancelled" : "active"))
                case .ambiguous(let id):
                    try batch.update("items", id: id, ["event_state": "ambiguous"])
                case .gone(let id):
                    try batch.update("items", id: id, ["event_state": "gone"])
                case .adoptBaseID(let ruleID, let baseID):
                    let rule = try AnnotationQueries.seriesRules(db).first { $0.id == ruleID }
                    try batch.update("series_rules", id: ruleID, ["base_ids": AnnotationQueries.encodeIDs((rule?.baseIDs ?? []) + [baseID])])
                }
            }
            return CommandOK(changed: !changes.isEmpty, message: "\(changes.count) annotation change(s)")

        case .resolveAnnotation(let id, let snap):
            guard try String.fetchOne(db, sql: "SELECT id FROM live_items WHERE id = ? AND kind = 'event_note'", arguments: [id]) != nil else {
                throw CommandFailure(.notFound, "Annotation \(id) not found.")
            }
            try batch.update("items", id: id, Self.snapshotFields(snap, state: "active"))
            return CommandOK(id: id)

        case .resolveLink(let table, let sourceID, let typed, let target):
            guard ["items", "tags"].contains(table) else { throw CommandFailure(.validation, "Unknown source \(table).") }
            let column = table == "tags" ? "page_body" : "body"
            guard let text = try String.fetchOne(db, sql: "SELECT \(column) FROM \(table) WHERE id = ? AND deleted_at IS NULL", arguments: [sourceID]) else {
                throw CommandFailure(.notFound, "Source \(sourceID) not found.")
            }
            guard let link = LinkParser.links(in: text).first(where: { $0.target == .missing(typed) }) else {
                return CommandOK(id: sourceID, changed: false)
            }
            let canonical = target.kind == .tag ? LinkParser.canonical(label: target.title, tag: target.id)
                                                : LinkParser.canonical(label: target.title, item: target.id)
            let updated = (text as NSString).replacingCharacters(in: link.range, with: canonical)
            let changed = try batch.update(table, id: sourceID, [column: updated])
            return CommandOK(id: sourceID, changed: !changed.isEmpty)

        case .reconcileSnoozes(let today):
            try Validate.day(today)
            let due = try Row.fetchAll(db, sql: """
                SELECT id, snoozed_until FROM live_items WHERE kind = 'task' AND status = 'snoozed' AND snoozed_until <= ?
                """, arguments: [today])
            for row in due {
                // Remember the scheduled return day for the "back from snooze" mark (F3).
                var fields: Fields = ["status": TaskStatus.open.rawValue, "snooze_ended_on": row["snoozed_until"] as String]
                fields.updateValue(nil, forKey: "snoozed_until")
                try batch.update("items", id: row["id"], fields)
            }
            return CommandOK(changed: !due.isEmpty, message: "\(due.count) snoozed task(s) reopened")
        }
    }

    // MARK: - Helpers

    static func snapshotFields(_ s: AppointmentSnapshot, state: String) -> Fields {
        var f: Fields = ["event_key": s.key, "event_series": s.seriesKey, "event_calendar": s.calendarID,
                         "event_start": s.start, "event_end": s.end, "event_state": state,
                         "title": s.title.isEmpty ? "Appointment" : s.title]
        f.updateValue(s.organizer, forKey: "event_organizer")
        return f
    }

    /// The notes row of a meeting, if it exists: the series document of a recurring meeting, else the occurrence row.
    static func meetingNotesRow(_ target: MeetingTarget, db: Database) throws -> String? {
        let s = target.snapshot
        if target.recurring {
            guard let rule = try AnnotationQueries.seriesRules(db).first(where: { $0.matches(s) }) else { return nil }
            return try String.fetchOne(db, sql: "SELECT id FROM live_items WHERE kind = 'event_note' AND series_rule = ? ORDER BY created_at LIMIT 1",
                                       arguments: [rule.id])
        }
        return try String.fetchOne(db, sql: "SELECT id FROM live_items WHERE kind = 'event_note' AND event_key = ? LIMIT 1", arguments: [s.key])
    }

    /// Saves notes, creating the series rule / notes row on the first non-empty text ("Nothing written" stores nothing).
    private func saveMeetingNotes(_ target: MeetingTarget, body: String, tags: [String]?, batch: Batch) throws -> CommandOK {
        let db = batch.db, s = target.snapshot
        var rowID = try Self.meetingNotesRow(target, db: db)
        if rowID == nil {
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(tags ?? []).isEmpty else { return CommandOK(changed: false) }
            let title = s.title.isEmpty ? "Meeting" : s.title
            if target.recurring {
                let ruleID = try AnnotationQueries.seriesRules(db).first(where: { $0.matches(s) })?.id
                    ?? batch.insert("series_rules", ["calendar_id": s.calendarID, "title": s.title, "organizer": s.organizer,
                                                     "base_ids": AnnotationQueries.encodeIDs([s.baseID])])
                rowID = try batch.insert("items", ["kind": "event_note", "title": title, "body": "", "series_rule": ruleID,
                                                   "event_calendar": s.calendarID, "event_start": s.start, "event_end": s.end,
                                                   "event_organizer": s.organizer, "event_state": "active"])
            } else {
                var fields = Self.snapshotFields(s, state: "active")
                fields["kind"] = "event_note"; fields["body"] = ""
                rowID = try batch.insert("items", fields)
            }
        }
        guard let id = rowID else { return CommandOK(changed: false) }
        let (text, unresolved) = try LinkResolver.resolve(body, db: db)
        var changed = !(try batch.update("items", id: id, ["body": text])).isEmpty
        if let tags { changed = try replaceTags(of: id, with: try tags.map(TagName.init), batch: batch) || changed }
        return CommandOK(id: id, changed: changed, unresolved: unresolved)
    }

    static func blockingFields(_ value: BlockingOverride?) -> Fields {
        var f: Fields = [:]
        f.updateValue(value?.rawValue, forKey: "blocking")
        return f
    }

    /// Item fields for a status change (status, snoozed_until, completed_at).
    private func statusFields(_ status: TaskStatus, snoozedUntil: String?, now: Date) throws -> Fields {
        var fields: Fields = ["status": status.rawValue]
        fields.updateValue(nil, forKey: "snooze_ended_on")      // a user status change ends the "back from snooze" mark
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

    private func requirePage(_ id: String, _ db: Database) throws {
        guard try Bool.fetchOne(db, sql: "SELECT 1 FROM live_items WHERE id = ? AND kind = 'info'", arguments: [id]) == true else {
            throw CommandFailure(.notFound, "Page \(id) not found.")
        }
    }

    static func session(of command: Command) -> String? {
        switch command {
        case .updateTask(_, let p): return p.session
        case .updatePage(_, let p): return p.session
        case .updateTagPage(_, _, let s): return s
        case .saveMeetingNotes(_, _, _, let s): return s
        case .updateMeetingNotes(_, _, _, let s): return s
        default: return nil
        }
    }

    /// The batch to append to when this save continues the writer's latest change in the same edit session (design P6).
    func coalescedBatch(_ command: Command, db: Database, writer: String) throws -> String? {
        guard let session = Self.session(of: command) else { return nil }
        let rowID: String?
        switch command {
        case .updateTask(let id, _), .updatePage(let id, _): rowID = id
        case .updateTagPage(let name, _, _):
            rowID = try String.fetchOne(db, sql: "SELECT id FROM live_tags WHERE name_key = ?", arguments: [TagName.key(for: name)])
        case .saveMeetingNotes(let target, _, _, _): rowID = try Self.meetingNotesRow(target, db: db)
        case .updateMeetingNotes(let id, _, _, _): rowID = id
        default: rowID = nil
        }
        guard let rowID,
              let latest = try Row.fetchOne(db, sql: """
                SELECT batch, session, undone FROM change_log WHERE writer = ? ORDER BY seq DESC LIMIT 1
                """, arguments: [writer]),
              latest["session"] as String? == session, latest["undone"] as Bool == false else { return nil }
        let batchID: String = latest["batch"]
        let touchesRow = try Bool.fetchOne(db, sql: "SELECT 1 FROM change_log WHERE batch = ? AND row_id = ? LIMIT 1", arguments: [batchID, rowID]) ?? false
        return touchesRow ? batchID : nil
    }

    /// Records the difference to the current remaining effort as an adjustment (task-progress P2). False when nothing changes.
    private func setRemaining(_ id: String, _ change: RemainingChange, batch: Batch) throws -> Bool {
        try Validate.day(change.day)
        guard change.minutes >= 0 else { throw CommandFailure(.validation, "The remaining effort can't be negative.") }
        let worked = try Int.fetchOne(batch.db, sql: "SELECT COALESCE(SUM(minutes), 0) FROM live_task_work WHERE item_id = ?", arguments: [id]) ?? 0
        let delta = (change.effortMinutes - worked) - change.minutes
        guard delta != 0 else { return false }
        try batch.insert("task_work", ["item_id": id, "day": change.day, "minutes": delta, "kind": WorkKind.adjust.rawValue])
        return true
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
