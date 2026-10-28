import Foundation

/// One part of a task: a checklist item with an optional effort (subtasks S1).
public struct TaskPart: Equatable, Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var effort: Effort?
    public var done: Bool
    public var position: Double
    public init(id: String, title: String, effort: Effort? = nil, done: Bool = false, position: Double = 0) {
        self.id = id; self.title = title; self.effort = effort; self.done = done; self.position = position
    }
}

/// A part as given to `replaceParts`/`createTask`: an existing id keeps and updates that part, no id adds one (subtasks S3).
public struct PartInput: Equatable, Codable, Sendable {
    public var id: String?
    public var title: String
    public var effort: Effort?
    public var done: Bool
    public init(id: String? = nil, title: String, effort: Effort? = nil, done: Bool = false) {
        self.id = id; self.title = title; self.effort = effort; self.done = done
    }
}

/// How recorded work came about (task-progress P1).
public enum WorkKind: String, Codable, CaseIterable, Sendable {
    /// "Done for today" in the day view.
    case part
    /// The remaining effort set by hand (the difference to before; negative when more is left).
    case adjust
    /// Recorded by an agent (`record_work`).
    case agent
}

/// Recorded work of one task on one day, of one kind (task page history).
public struct WorkEntry: Equatable, Sendable {
    public let day: String
    public let kind: WorkKind
    public let minutes: Int
}

public enum TaskStatus: String, Codable, CaseIterable {
    case open, snoozed, done, dropped
}

/// How much work a task is (specs/daily-planning "Effort sizes").
public enum Effort: String, Codable, CaseIterable, Comparable, Sendable {
    case xs = "XS", s = "S", m = "M", l = "L", xl = "XL"
    var rank: Int { Effort.allCases.firstIndex(of: self)! }
    public static func < (a: Effort, b: Effort) -> Bool { a.rank < b.rank }
}

public enum Priority: String, Codable, CaseIterable, Comparable {
    case none, low, normal, high, urgent

    /// Sort rank: urgent = 4 … none = 0.
    public var rank: Int {
        switch self { case .none: 0; case .low: 1; case .normal: 2; case .high: 3; case .urgent: 4 }
    }
    public static func < (a: Priority, b: Priority) -> Bool { a.rank < b.rank }
}

/// Floating local due date with optional wall-clock time (design L3).
public struct Due: Codable, Equatable {
    /// YYYY-MM-DD
    public var day: String
    /// HH:mm, nil = whole day
    public var time: String?
    public init(day: String, time: String? = nil) { self.day = day; self.time = time }
}

/// A task as read from the store.
public extension TaskItem {
    /// Snoozed and its return day hasn't arrived yet ("not now").
    func isSnoozed(today: LocalDay) -> Bool {
        status == .snoozed && (snoozedUntil.flatMap(LocalDay.init).map { $0 > today } ?? false)
    }

    /// Comes back from a snooze on `day`: woken that day, or still snoozed until it (not woken yet, or a forecast) — F3.
    func isBackFromSnooze(on day: LocalDay) -> Bool {
        snoozeEndedOn == day.description || (status == .snoozed && snoozedUntil == day.description)
    }

    /// At least one part has an effort: the parts drive the remaining effort (subtasks S2).
    var hasEstimatedParts: Bool { parts.contains { $0.effort != nil } }

    /// The remaining effort: with estimated parts the sum of the open ones' efforts (specs/daily-planning "Remaining effort
    /// from parts"); otherwise effort minus recorded work, never below zero; nil without either (specs/tasks "Remaining effort").
    func remaining(sizes: EffortSizes) -> Int? {
        if hasEstimatedParts {
            return parts.filter { !$0.done }.compactMap(\.effort).reduce(0) { $0 + sizes[$1] }
        }
        return effort.map { max(0, sizes[$0] - workedMinutes) }
    }

    /// The snooze date shown with the "back from snooze" mark.
    var snoozeReturnDay: String? { status == .snoozed ? snoozedUntil : snoozeEndedOn }
}

public struct TaskItem: Equatable, Identifiable {
    public let id: String
    public var title: String
    public var body: String
    public var status: TaskStatus
    public var priority: Priority
    public var due: Due?
    public var snoozedUntil: String?
    public var tags: [String]
    public var createdAt: Date
    public var modifiedAt: Date
    public var modifiedBy: String
    public var completedAt: Date?
    public var effort: Effort?
    /// The day the task last came back from a snooze (set when the snooze ends, cleared by the next status change).
    public var snoozeEndedOn: String?
    /// Work recorded on the task, in minutes (task-progress P1); may include negative adjustments.
    public var workedMinutes = 0
    /// Parts in order (subtasks S1).
    public var parts: [TaskPart] = []
}

extension Due {
    /// The moment this due date refers to in `calendar`'s time zone: the given wall-clock time,
    /// or the start of the day for whole-day tasks. Floating: the same Due maps to the local day wherever you are.
    public func date(in calendar: Calendar = .current) -> Date? {
        guard let day = LocalDay(day) else { return nil }
        let start = day.interval(in: calendar).start
        guard let time else { return start }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return start }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: start)
    }

    /// Creates a Due from a picked date, optionally keeping its wall-clock time.
    public init(date: Date, includeTime: Bool, calendar: Calendar = .current) {
        self.day = LocalDay(date: date, calendar: calendar).description
        if includeTime {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            self.time = String(format: "%02d:%02d", c.hour!, c.minute!)
        } else {
            self.time = nil
        }
    }
}
