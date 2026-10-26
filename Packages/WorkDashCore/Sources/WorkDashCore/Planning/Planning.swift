import Foundation
import GRDB

/// Working minutes per effort size (specs/daily-planning "Effort sizes").
public struct EffortSizes: Equatable, Codable {
    public var minutes: [Effort: Int]
    public init(minutes: [Effort: Int]) { self.minutes = minutes }

    /// Defaults: 30 min, 2 h, 4 h, 1 working day, 3 working days.
    public static func defaults(for hours: WorkingHours) -> EffortSizes {
        let day = max(60, hours.minutesPerDay)
        return EffortSizes(minutes: [.xs: 30, .s: 120, .m: 240, .l: day, .xl: 3 * day])
    }

    public subscript(_ e: Effort) -> Int { minutes[e] ?? 0 }
}

/// Urgency of a task relative to its effort and the free time until its due date (specs/daily-planning "Work on states").
public enum WorkOnState: String, Codable, CaseIterable, Comparable {
    case late, tight, startToday = "start_today", ok, noEstimate = "no_estimate"
    var rank: Int { WorkOnState.allCases.firstIndex(of: self)! }
    public static func < (a: WorkOnState, b: WorkOnState) -> Bool { a.rank < b.rank }
}

public struct WorkOnItem: Equatable, Identifiable {
    public var id: String { task.id }
    public let task: TaskItem
    public let effortMinutes: Int?
    /// Free working minutes from now until the task's deadline.
    public let freeMinutes: Double
    public let state: WorkOnState
}

public enum Planning {
    /// late < effort ≤ tight < 1.5× ≤ start today < 2× (or due tomorrow) ≤ ok.
    public static func state(effortMinutes: Int?, freeMinutes: Double, dueTomorrow: Bool) -> WorkOnState {
        guard let e = effortMinutes.map(Double.init) else { return .noEstimate }
        if freeMinutes < e { return .late }
        if freeMinutes < 1.5 * e { return .tight }
        if freeMinutes < 2 * e || dueTomorrow { return .startToday }
        return .ok
    }

    /// The moment a task must be done by: its due time, or the end of its due day.
    public static func deadline(of task: TaskItem, calendar: Calendar = .current) -> Date? {
        guard let due = task.due, let day = LocalDay(due.day) else { return nil }
        if due.time != nil { return due.date(in: calendar) }
        return day.interval(in: calendar).end
    }

    /// Evaluates each task on its own (no sharing of free time), sorted by state, due date, priority.
    public static func evaluate(_ tasks: [TaskItem], now: Date, sizes: EffortSizes, hours: WorkingHours,
                                busy: [(interval: DateInterval, weight: BlockingWeight)], calendar: Calendar = .current) -> [WorkOnItem] {
        let tomorrow = LocalDay(date: now, calendar: calendar).adding(days: 1, calendar: calendar).description
        let items = tasks.compactMap { task -> WorkOnItem? in
            guard let deadline = deadline(of: task, calendar: calendar) else { return nil }
            let free = FreeTime.minutes(from: now, to: deadline, busy: busy, hours: hours, calendar: calendar)
            let effort = task.effort.map { sizes[$0] }
            return WorkOnItem(task: task, effortMinutes: effort, freeMinutes: free,
                              state: state(effortMinutes: effort, freeMinutes: free, dueTomorrow: task.due?.day == tomorrow))
        }
        return items.sorted { a, b in
            if a.state != b.state { return a.state < b.state }
            let da = a.task.due?.day ?? "", dbb = b.task.due?.day ?? ""
            if da != dbb { return da < dbb }
            return a.task.priority > b.task.priority
        }
    }
}

extension TaskQueries {
    /// Open tasks due from tomorrow to `today + horizon` days; snoozed tasks only once their snooze date has come.
    public static func upcoming(_ db: Database, today: LocalDay, horizon: Int) throws -> [TaskItem] {
        try fetchTasks(db, sql: """
            SELECT i.* FROM live_items i
            WHERE i.kind = 'task' AND \(effectivelyOpenSQL) AND i.due_day > :today AND i.due_day <= :last
            ORDER BY \(openOrderSQL)
            """, arguments: ["today": today.description, "last": today.adding(days: max(0, horizon)).description])
    }
}
