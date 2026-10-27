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

/// Why a task is on today's list (specs/daily-planning "Today list").
public enum TodayReason: String, Codable, Comparable {
    case overdue, dueToday = "due_today", needsWork = "needs_work"
    var rank: Int { switch self { case .overdue: 0; case .dueToday: 1; case .needsWork: 2 } }
    public static func < (a: TodayReason, b: TodayReason) -> Bool { a.rank < b.rank }
}

public struct TodayItem: Equatable, Identifiable {
    public var id: String { task.id }
    public let task: TaskItem
    public let reason: TodayReason
    public let effortMinutes: Int?
    /// Minimum work needed today to finish by the due date (nil without estimate).
    public let neededToday: Int?
    /// Even all free time until the due date isn't enough.
    public let cantFit: Bool
}

public struct ComingUpItem: Equatable, Identifiable {
    public var id: String { task.id }
    public let task: TaskItem
    public let effortMinutes: Int?
    /// Last day to start and still finish (nil without estimate).
    public let startBy: LocalDay?
}

public struct DayPlan: Equatable {
    public var today: [TodayItem] = []
    public var comingUp: [ComingUpItem] = []
    /// Sum of work needed today.
    public var neededMinutes: Int = 0
    /// Today-list tasks without an estimate.
    public var withoutEstimate: Int = 0
    public init() {}
}

public enum Planning {
    /// The moment a task must be done by: its due time, or the end of its due day.
    public static func deadline(of task: TaskItem, calendar: Calendar = .current) -> Date? {
        guard let due = task.due, let day = LocalDay(due.day) else { return nil }
        if due.time != nil { return due.date(in: calendar) }
        return day.interval(in: calendar).end
    }

    /// Plans today (design Q7): each task on its own against the free time until its deadline.
    public static func plan(_ tasks: [TaskItem], now: Date, sizes: EffortSizes, hours: WorkingHours,
                            busy: [(interval: DateInterval, weight: BlockingWeight)], calendar: Calendar = .current) -> DayPlan {
        let today = LocalDay(date: now, calendar: calendar)
        let tomorrowStart = today.adding(days: 1, calendar: calendar).interval(in: calendar).start
        func free(_ from: Date, _ to: Date) -> Double { FreeTime.minutes(from: from, to: to, busy: busy, hours: hours, calendar: calendar) }

        var plan = DayPlan()
        var seen = Set<String>()
        for task in tasks where seen.insert(task.id).inserted {
            guard let due = task.due, let dueDay = LocalDay(due.day), let deadline = deadline(of: task, calendar: calendar) else { continue }
            let effort = task.effort.map { sizes[$0] }
            let reason: TodayReason? = dueDay < today ? .overdue : (dueDay == today ? .dueToday : nil)
            if let e = effort {
                let freeUntil = free(now, deadline)
                let needed = reason != nil ? e : max(0, e - Int(free(tomorrowStart, deadline).rounded(.down)))
                if reason != nil || needed > 0 {
                    plan.today.append(TodayItem(task: task, reason: reason ?? .needsWork, effortMinutes: e, neededToday: needed,
                                                cantFit: Double(e) > freeUntil))
                    plan.neededMinutes += needed
                } else {
                    let start = startBy(effort: e, deadline: deadline, today: today, dueDay: dueDay, now: now, free: free, calendar: calendar)
                    plan.comingUp.append(ComingUpItem(task: task, effortMinutes: e, startBy: start))
                }
            } else if let reason {
                plan.today.append(TodayItem(task: task, reason: reason, effortMinutes: nil, neededToday: nil, cantFit: false))
                plan.withoutEstimate += 1
            } else {
                plan.comingUp.append(ComingUpItem(task: task, effortMinutes: nil, startBy: nil))
            }
        }
        plan.today.sort { a, b in
            if a.cantFit != b.cantFit { return a.cantFit }
            if a.reason != b.reason { return a.reason < b.reason }
            if a.task.priority != b.task.priority { return a.task.priority > b.task.priority }
            return (a.task.due?.day ?? "") < (b.task.due?.day ?? "")
        }
        plan.comingUp.sort { a, b in
            switch (a.startBy, b.startBy) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return (a.task.due?.day ?? "") < (b.task.due?.day ?? "")
            }
        }
        return plan
    }

    /// The latest day from which the free time until the deadline still covers the effort.
    static func startBy(effort: Int, deadline: Date, today: LocalDay, dueDay: LocalDay, now: Date,
                        free: (Date, Date) -> Double, calendar: Calendar) -> LocalDay? {
        var day = dueDay
        while day >= today {
            let from = day == today ? now : day.interval(in: calendar).start
            if free(from, deadline) >= Double(effort) { return day }
            day = day.adding(days: -1, calendar: calendar)
        }
        return nil
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

    /// Tasks still snoozed on `day` (snooze date after it), by snooze date: the "N snoozed" summary (future-day-planning F5).
    /// A task snoozed until `day` itself is back that day and appears in that day's lists instead.
    public static func snoozed(_ db: Database, after day: LocalDay) throws -> [TaskItem] {
        try fetchTasks(db, sql: """
            SELECT i.* FROM live_items i
            WHERE i.kind = 'task' AND i.status = 'snoozed' AND i.snoozed_until > :day
            ORDER BY i.snoozed_until, \(openOrderSQL)
            """, arguments: ["day": day.description])
    }
}
