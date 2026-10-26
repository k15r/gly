import Foundation
import GRDB
import MCP
import WorkDashCore

/// Executes the MCP tools against the store and the calendar (design M3). Transport-independent:
/// `WorkDashMCPServer` calls it for stdio (via XPC) and HTTP alike.
public final class WorkDashTools: @unchecked Sendable {
    let reader: DatabaseReader
    let handler: CommandHandler
    let calendar: EventSource
    let hiddenCalendarIDs: () -> Set<String>
    let deviceID: String
    let now: () -> Date
    /// Working hours, effort sizes and horizon (shared settings).
    let planning: () -> (WorkingHours, EffortSizes, Int)

    public init(writer: DatabaseWriter, calendar: EventSource, hiddenCalendarIDs: @escaping () -> Set<String>,
                deviceID: String, now: @escaping () -> Date = Date.init,
                planning: @escaping () -> (WorkingHours, EffortSizes, Int) = { (WorkingHours(), .defaults(for: WorkingHours()), 5) }) {
        self.reader = writer
        self.handler = CommandHandler(writer: writer)
        self.calendar = calendar
        self.hiddenCalendarIDs = hiddenCalendarIDs
        self.deviceID = deviceID
        self.now = now
        self.planning = planning
    }

    var today: LocalDay { LocalDay(date: now()) }

    /// Writer recorded for an agent change, e.g. `agent:claude-code@mac-3f9a1c` (design M4).
    public func writer(client: String?) -> String {
        "agent:\(Self.sanitize(client))@\(deviceID)"
    }

    static func sanitize(_ client: String?) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        let cleaned = String((client ?? "").lowercased().map { allowed.contains($0) ? $0 : "-" }.prefix(40))
        return cleaned.isEmpty ? "unknown" : cleaned
    }

    // MARK: - Dispatch

    public func call(_ name: String, arguments: [String: Value]?, client: String?) async -> CallTool.Result {
        let args = Arguments(arguments ?? [:])
        do {
            let value: Value
            switch name {
            case "get_schedule": value = try await getSchedule(args)
            case "list_tasks": value = try listTasks(args)
            case "get_task": value = try taskWithLinks(args.requiredString("id"))
            case "list_tags": value = try listTags(args)
            case "create_task": value = try createTask(args, writer: writer(client: client))
            case "update_task": value = try updateTask(args, writer: writer(client: client))
            case "delete_task": value = try deleteTask(args, writer: writer(client: client))
            case "create_page": value = try createPage(args, writer: writer(client: client))
            case "get_page": value = try pageValue(args.requiredString("id"))
            case "update_page": value = try updatePage(args, writer: writer(client: client))
            case "delete_page": value = try deletePage(args, writer: writer(client: client))
            case "search": value = try search(args)
            case "get_context": value = try context(args)
            case "get_tag_page": value = try tagPage(args)
            case "update_tag_page": value = try updateTagPage(args, writer: writer(client: client))
            default: throw ToolError("Unknown tool \(name).")
            }
            return CallTool.Result(content: [Self.text(Self.json(value))], structuredContent: Optional.some(value))
        } catch let error as ToolError {
            return CallTool.Result(content: [Self.text(error.message)], isError: true)
        } catch let failure as CommandFailure {
            return CallTool.Result(content: [Self.text(failure.message)], isError: true)
        } catch let invalid as TagName.Invalid {
            return CallTool.Result(content: [Self.text(invalid.description)], isError: true)
        } catch {
            return CallTool.Result(content: [Self.text("Internal error: \(error)")], isError: true)
        }
    }

    static func text(_ s: String) -> Tool.Content { .text(text: s, annotations: nil, _meta: nil) }

    // MARK: - Read tools

    func getSchedule(_ args: Arguments) async throws -> Value {
        let today = self.today
        let day = try args.day("date") ?? today
        let tasks = try await reader.read { try TaskQueries.tasksForDay($0, day: day, today: today) }
        var result: [String: Value] = ["date": .string(day.description)]
        if calendar.authorization == .notDetermined { _ = await calendar.requestAccess() }
        let (hours, sizes, horizon) = planning()
        let overrides = try await reader.read { try AnnotationQueries.overrides($0) }
        if calendar.authorization.canRead {
            let calendars = calendar.calendars()
            let visible = Set(calendars.map(\.id)).subtracting(hiddenCalendarIDs())
            let model = DayModel(day: day, now: now(), appointments: calendar.appointments(overlapping: day.interval(), calendarIDs: visible),
                                 calendars: calendars, tasks: tasks)
            result["appointments"] = .array((model.allDay + model.timed).map { entry in
                guard case .object(var o) = encode(entry) else { return .null }
                let (weight, reason) = overrides.classify(entry.appointment)
                o["counts_as"] = .string(weight.rawValue)
                o["reason"] = .string(Self.reasonText(reason))
                return .object(o)
            })
            let dayStart = day == today ? now() : day.interval().start
            result["free_minutes"] = .int(Int(FreeTime.minutes(from: dayStart, to: day.interval().end,
                                                               busy: overrides.busy(model.allDay.map(\.appointment) + model.timed.map(\.appointment)),
                                                               hours: hours).rounded()))
            if day == today {
                let range = DateInterval(start: today.interval().start, end: today.adding(days: horizon).interval().end)
                let upcoming = try await reader.read { try TaskQueries.upcoming($0, today: today, horizon: horizon) }
                let busy = overrides.busy(calendar.appointments(overlapping: range, calendarIDs: visible))
                let plan = Planning.plan(tasks.map(\.task) + upcoming, now: now(), sizes: sizes, hours: hours, busy: busy)
                result["today"] = .array(plan.today.map { item in
                    guard case .object(var o) = encode(item.task) else { return .null }
                    o["reason"] = .string(item.reason.rawValue)
                    o["effort_minutes"] = item.effortMinutes.map { .int($0) } ?? .null
                    o["needed_today_minutes"] = item.neededToday.map { .int($0) } ?? .null
                    o["cant_fit"] = .bool(item.cantFit)
                    return .object(o)
                })
                result["needed_today_minutes"] = .int(plan.neededMinutes)
                result["without_estimate"] = .int(plan.withoutEstimate)
                result["coming_up"] = .array(plan.comingUp.map { item in
                    guard case .object(var o) = encode(item.task) else { return .null }
                    o["effort_minutes"] = item.effortMinutes.map { .int($0) } ?? .null
                    o["start_by"] = item.startBy.map { .string($0.description) } ?? .null
                    return .object(o)
                })
            }
        } else {
            result["appointments"] = .array([])
            result["appointments_unavailable"] = "WorkDash has no calendar access (System Settings → Privacy & Security → Calendars)."
        }
        result["tasks"] = .array(tasks.map { t in
            guard case .object(var o) = encode(t.task) else { return .null }
            o["overdue"] = .bool(t.isOverdue)
            return .object(o)
        })
        return .object(result)
    }

    static func reasonText(_ r: BlockingReason) -> String {
        switch r { case .automatic: "automatic"; case .occurrenceOverride: "override (this occurrence)"; case .seriesOverride: "override (series)" }
    }

    func listTasks(_ args: Arguments) throws -> Value {
        let statuses: Set<TaskStatus>
        switch try args.string("status") ?? "open" {
        case "open": statuses = [.open, .snoozed]
        case "all": statuses = []
        case let s:
            guard let status = TaskStatus(rawValue: s) else { throw ToolError("Unknown status “\(s)” (use open, snoozed, done, dropped or all).") }
            statuses = [status]
        }
        let filter = TaskFilter(statuses: statuses,
                                tag: try args.string("tag").map(TagName.init),
                                dueBefore: try args.day("due_before")?.description,
                                dueAfter: try args.day("due_after")?.description,
                                text: try args.string("text"),
                                limit: min(500, max(1, try args.int("limit") ?? 50)))
        let page = try reader.read { try TaskQueries.find($0, filter) }
        return .object(["tasks": .array(page.tasks.map(encode)), "has_more": .bool(page.hasMore)])
    }

    func task(_ id: String) throws -> TaskItem {
        guard let task = try reader.read({ try TaskQueries.task($0, id: id) }) else { throw ToolError("Task \(id) not found.") }
        return task
    }

    func listTags(_ args: Arguments) throws -> Value {
        let today = self.today.description
        let tags = try reader.read { try TagQueries.list($0, prefix: try args.string("prefix"), today: today) }
        return .object(["tags": .array(tags.map { .object(["name": .string($0.name), "open_tasks": .int($0.openCount)]) })])
    }

    // MARK: - Write tools

    func createTask(_ args: Arguments, writer: String) throws -> Value {
        let draft = TaskDraft(title: try args.requiredString("title"),
                              body: try args.string("notes") ?? "",
                              priority: try args.priority("priority") ?? .none,
                              due: try args.due(),
                              tags: try args.strings("tags") ?? [],
                              effort: try args.effort("effort") ?? nil)
        let ok = try performOK(.createTask(draft), writer: writer)
        return withUnresolved(encode(try task(ok.id ?? "")), ok.unresolved)
    }

    func updateTask(_ args: Arguments, writer: String) throws -> Value {
        let id = try args.requiredString("id")
        var patch = TaskPatch()
        patch.title = try args.string("title")
        patch.body = try args.string("notes")
        patch.priority = try args.priority("priority")
        if args.has("due_date") { patch.due = .some(try args.due()) }
        else if args.has("due_time") { throw ToolError("due_time needs due_date.") }
        patch.tags = try args.strings("tags")
        if args.has("effort") { patch.effort = .some(try args.effort("effort") ?? nil) }
        if let s = try args.string("status") {
            guard let status = TaskStatus(rawValue: s) else { throw ToolError("Unknown status “\(s)” (use open, snoozed, done or dropped).") }
            if status == .snoozed && !args.has("snoozed_until") { throw ToolError("A snooze date (snoozed_until) is required to snooze a task.") }
            patch.status = status
            patch.snoozedUntil = try args.day("snoozed_until")?.description
        }
        _ = try task(id)    // not found → clear error before anything else
        let ok = try performOK(.updateTask(id: id, patch), writer: writer)
        return withUnresolved(encode(try task(id)), ok.unresolved)
    }

    func deleteTask(_ args: Arguments, writer: String) throws -> Value {
        let id = try args.requiredString("id")
        _ = try task(id)
        _ = try perform(.deleteTask(id: id), writer: writer)
        return .object(["deleted": .string(id)])
    }

    @discardableResult
    func perform(_ command: Command, writer: String) throws -> String {
        try performOK(command, writer: writer).id ?? ""
    }

    func performOK(_ command: Command, writer: String) throws -> CommandOK {
        switch handler.perform(command, writer: writer) {
        case .ok(let ok): return ok
        case .failure(let f): throw f
        }
    }

    func withUnresolved(_ value: Value, _ unresolved: [String]?) -> Value {
        guard case .object(var o) = value else { return value }
        o["unresolved"] = .array((unresolved ?? []).map { .string($0) })
        return .object(o)
    }

    // MARK: - Pages, links, search, tag pages

    func taskWithLinks(_ id: String) throws -> Value {
        guard case .object(var o) = encode(try task(id)) else { return .null }
        try addLinks(&o, table: "items", id: id)
        return .object(o)
    }

    func page(_ id: String) throws -> PageItem {
        guard let page = try reader.read({ try PageQueries.page($0, id: id) }) else { throw ToolError("Page \(id) not found.") }
        return page
    }

    func pageValue(_ id: String) throws -> Value {
        let p = try page(id)
        var o: [String: Value] = [
            "id": .string(p.id), "title": .string(p.title), "text": .string(p.body),
            "tags": .array(p.tags.map { .string($0) }),
            "created_at": .string(Self.timestamp.string(from: p.createdAt)),
            "modified_at": .string(Self.timestamp.string(from: p.modifiedAt)),
            "modified_by": .string(p.modifiedBy),
        ]
        try addLinks(&o, table: "items", id: id)
        return .object(o)
    }

    func addLinks(_ o: inout [String: Value], table: String, id: String, isTag: Bool = false) throws {
        let (outgoing, backlinks) = try reader.read { db in
            (try LinkQueries.outgoing(db, sourceTable: table, sourceID: id), try LinkQueries.backlinks(db, to: id, isTag: isTag))
        }
        o["links"] = .array(outgoing.map(encode))
        o["backlinks"] = .array(backlinks.map { b in
            .object(["id": .string(b.source.id), "kind": .string(b.source.kind.rawValue), "title": .string(b.source.title), "excerpt": .string(b.excerpt)])
        })
    }

    func encode(_ link: OutgoingLink) -> Value {
        switch link.target {
        case .live(let r): return .object(["id": .string(r.id), "kind": .string(r.kind.rawValue), "title": .string(r.title), "state": "live"])
        case .deleted(let r): return .object(["id": .string(r.id), "kind": .string(r.kind.rawValue), "title": .string(r.title), "state": "deleted"])
        case .missing(let t): return .object(["id": .null, "kind": "page", "title": .string(t), "state": "missing"])
        }
    }

    func encode(_ ref: LinkRef) -> Value {
        .object(["id": .string(ref.id), "kind": .string(ref.kind.rawValue), "title": .string(ref.title)])
    }

    func createPage(_ args: Arguments, writer: String) throws -> Value {
        let draft = PageDraft(title: try args.requiredString("title"), body: try args.string("text") ?? "", tags: try args.strings("tags") ?? [])
        let ok = try performOK(.createPage(draft), writer: writer)
        return withUnresolved(try pageValue(ok.id ?? ""), ok.unresolved)
    }

    func updatePage(_ args: Arguments, writer: String) throws -> Value {
        let id = try args.requiredString("id")
        _ = try page(id)
        let patch = PagePatch(title: try args.string("title"), body: try args.string("text"), tags: try args.strings("tags"))
        let ok = try performOK(.updatePage(id: id, patch), writer: writer)
        return withUnresolved(try pageValue(id), ok.unresolved)
    }

    func deletePage(_ args: Arguments, writer: String) throws -> Value {
        let id = try args.requiredString("id")
        _ = try page(id)
        try perform(.deletePage(id: id), writer: writer)
        return .object(["deleted": .string(id)])
    }

    func search(_ args: Arguments) throws -> Value {
        let query = try args.requiredString("query")
        var kinds: Set<LinkRef.Kind> = [.page, .task, .tag]
        if let k = try args.string("kind") {
            guard let kind = LinkRef.Kind(rawValue: k) else { throw ToolError("Unknown kind “\(k)” (use page, task or tag).") }
            kinds = [kind]
        }
        let limit = min(100, max(1, try args.int("limit") ?? 10))
        let results = try reader.read { try SearchQueries.search($0, query, kinds: kinds, limit: limit) }
        return .object(["results": .array(results.all.map { hit in
            .object(["id": .string(hit.ref.id), "kind": .string(hit.ref.kind.rawValue), "title": .string(hit.ref.title), "excerpt": .string(hit.excerpt)])
        })])
    }

    func context(_ args: Arguments) throws -> Value {
        if let name = try args.string("tag") {
            let tag = try TagName(name)
            let today = self.today
            let data = try reader.read { try TagPageQueries.page($0, name: tag, today: today) }
            var o: [String: Value] = ["tag": .string(data.name)]
            if let tagID = data.tagID { try addLinks(&o, table: "tags", id: tagID, isTag: true) } else { o["links"] = .array([]); o["backlinks"] = .array([]) }
            o["tagged"] = .array(data.openTasks.map { encode(LinkRef(kind: .task, id: $0.id, title: $0.title)) }
                                 + data.pages.map { encode(LinkRef(kind: .page, id: $0.id, title: $0.title)) }
                                 + data.finishedTasks.map { encode(LinkRef(kind: .task, id: $0.id, title: $0.title)) })
            return .object(o)
        }
        let id = try args.requiredString("id")
        guard let (ref, deleted) = try reader.read({ try LinkQueries.reference($0, id: id, isTag: false) }), !deleted else {
            throw ToolError("Item \(id) not found.")
        }
        var o: [String: Value] = ["item": encode(ref)]
        try addLinks(&o, table: "items", id: ref.id)
        return .object(o)
    }

    func tagPage(_ args: Arguments) throws -> Value {
        let tag = try TagName(try args.requiredString("name"))
        let today = self.today
        let data = try reader.read { try TagPageQueries.page($0, name: tag, today: today) }
        return .object([
            "name": .string(data.name), "text": .string(data.body),
            "open_tasks": .array(data.openTasks.map(encode)),
            "pages": .array(data.pages.map { encode(LinkRef(kind: .page, id: $0.id, title: $0.title)) }),
            "finished_tasks": .array(data.finishedTasks.map(encode)),
        ])
    }

    func updateTagPage(_ args: Arguments, writer: String) throws -> Value {
        let name = try args.requiredString("name")
        guard let text = try args.string("text") else { throw ToolError("text is required.") }
        let ok = try performOK(.updateTagPage(name: name, body: text), writer: writer)
        return withUnresolved(try tagPage(Arguments(["name": .string(name)])), ok.unresolved)
    }

    // MARK: - Encoding

    static let timestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func encode(_ t: TaskItem) -> Value {
        var o: [String: Value] = [
            "id": .string(t.id), "title": .string(t.title), "notes": .string(t.body),
            "status": .string(t.status.rawValue), "priority": .string(t.priority.rawValue),
            "tags": .array(t.tags.map { .string($0) }),
            "created_at": .string(Self.timestamp.string(from: t.createdAt)),
            "modified_at": .string(Self.timestamp.string(from: t.modifiedAt)),
            "modified_by": .string(t.modifiedBy),
        ]
        if let due = t.due {
            var d: [String: Value] = ["day": .string(due.day)]
            if let time = due.time { d["time"] = .string(time) }
            o["due"] = .object(d)
        } else {
            o["due"] = .null
        }
        o["snoozed_until"] = t.snoozedUntil.map { .string($0) } ?? .null
        o["effort"] = t.effort.map { .string($0.rawValue) } ?? .null
        return .object(o)
    }

    func encode(_ entry: DayAppointment) -> Value {
        let a = entry.appointment
        var o: [String: Value] = [
            "title": .string(a.title),
            "start": .string(Self.timestamp.string(from: a.start)),
            "end": .string(Self.timestamp.string(from: a.end)),
            "all_day": .bool(a.isAllDay), "cancelled": .bool(a.isCancelled),
            "calendar": .string(entry.calendar.map { "\($0.title) (\($0.sourceTitle))" } ?? ""),
            "attendees": .array(a.attendees.map { .string($0) }),
        ]
        o["location"] = a.location.flatMap { $0.isEmpty ? nil : .string($0) } ?? .null
        o["organizer"] = a.organizer.map { .string($0) } ?? .null
        return .object(o)
    }

    static func json(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

struct ToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Typed access to tool arguments with clear messages for the model.
struct Arguments {
    let values: [String: Value]
    init(_ values: [String: Value]) { self.values = values }

    func has(_ key: String) -> Bool { values[key] != nil }

    func string(_ key: String) throws -> String? {
        switch values[key] {
        case nil, .null: return nil
        case .string(let s): return s
        default: throw ToolError("\(key) must be a string.")
        }
    }

    func requiredString(_ key: String) throws -> String {
        guard let s = try string(key), !s.trimmingCharacters(in: .whitespaces).isEmpty else { throw ToolError("\(key) is required.") }
        return s
    }

    func int(_ key: String) throws -> Int? {
        switch values[key] {
        case nil, .null: return nil
        case .int(let i): return i
        case .double(let d) where d == d.rounded(): return Int(d)
        default: throw ToolError("\(key) must be an integer.")
        }
    }

    func strings(_ key: String) throws -> [String]? {
        switch values[key] {
        case nil, .null: return nil
        case .array(let items):
            return try items.map { item in
                guard case .string(let s) = item else { throw ToolError("\(key) must be a list of strings.") }
                return s
            }
        default: throw ToolError("\(key) must be a list of strings.")
        }
    }

    func day(_ key: String) throws -> LocalDay? {
        guard let s = try string(key) else { return nil }
        guard let d = LocalDay(s) else { throw ToolError("\(key) “\(s)” is not a date (YYYY-MM-DD).") }
        return d
    }

    /// nil = absent; .some(nil) = explicitly null (remove).
    func effort(_ key: String) throws -> Effort?? {
        guard has(key) else { return nil }
        guard let s = try string(key) else { return .some(nil) }
        guard let e = Effort(rawValue: s.uppercased()) else { throw ToolError("Unknown effort “\(s)” (use XS, S, M, L or XL).") }
        return .some(e)
    }

    func priority(_ key: String) throws -> Priority? {
        guard let s = try string(key) else { return nil }
        guard let p = Priority(rawValue: s) else { throw ToolError("Unknown priority “\(s)” (use none, low, normal, high or urgent).") }
        return p
    }

    /// `due_date` (+ optional `due_time`); nil when absent or null.
    func due() throws -> Due? {
        guard let day = try day("due_date") else {
            if try string("due_time") != nil { throw ToolError("due_time needs due_date.") }
            return nil
        }
        return Due(day: day.description, time: try string("due_time"))
    }
}
