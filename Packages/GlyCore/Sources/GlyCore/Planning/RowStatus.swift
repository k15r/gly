import Foundation

/// Durations as gly shows them: working days when at least a day ("1d 2h"), otherwise hours and minutes.
public enum Durations {
    public static func effort(_ minutes: Double, dayLength: Int) -> String {
        let total = Int(minutes.rounded()), day = max(60, dayLength)
        guard total >= day else { return clock(minutes) }
        let d = total / day, rest = total % day
        return rest == 0 ? "\(d)d" : "\(d)d " + clock(Double(rest))
    }

    public static func clock(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

/// The status a task row shows (specs/appearance "Status colors", "Task rows"; status-colors C2). One per row: the strongest.
public enum StatusKind: Int, Comparable, Sendable, CaseIterable {
    // Strongest first.
    case cantFit, overdue, dueToday, needsWork, backFromSnooze, done
    public static func < (a: StatusKind, b: StatusKind) -> Bool { a.rawValue < b.rawValue }
}

public struct RowStatus: Equatable, Sendable {
    public let kind: StatusKind
    /// The reason, for the tooltip.
    public let tooltip: String
}

public extension RowStatus {
    /// The status of `task` on `day` (the day view's day, or today in lists); `plan` is its Today-list entry for that day, if any.
    static func of(_ task: TaskItem, day: LocalDay, today: LocalDay, plan: TodayItem?, dayLength: Int,
                   calendar: Calendar = .current) -> RowStatus? {
        func name(_ d: LocalDay) -> String {
            if d == today { return "today" }
            if d == today.adding(days: -1, calendar: calendar) { return "yesterday" }
            if d == today.adding(days: 1, calendar: calendar) { return "tomorrow" }
            let f = DateFormatter(); f.calendar = calendar; f.setLocalizedDateFormatFromTemplate("EEE d MMM")
            return f.string(from: d.interval(in: calendar).start)
        }
        if task.status == .done { return RowStatus(kind: .done, tooltip: "Done") }
        guard task.status != .dropped else { return nil }
        let dueDay = task.due.flatMap { LocalDay($0.day) }
        if plan?.cantFit == true, let dueDay {
            return RowStatus(kind: .cantFit, tooltip: "Can't fit: even all free time until it's due (\(name(dueDay))) isn't enough")
        }
        if let dueDay, dueDay < day { return RowStatus(kind: .overdue, tooltip: "Overdue since \(name(dueDay))") }
        if let dueDay, dueDay == day { return RowStatus(kind: .dueToday, tooltip: "Due \(name(day))") }
        if let plan, plan.reason == .needsWork, let needed = plan.neededToday, needed > 0, let dueDay {
            return RowStatus(kind: .needsWork,
                             tooltip: "At least \(Durations.effort(Double(needed), dayLength: dayLength)) \(name(day)) to finish by \(name(dueDay))")
        }
        if task.isBackFromSnooze(on: day) {
            let was = task.snoozeReturnDay.flatMap(LocalDay.init).map(name) ?? name(day)
            let due = dueDay.map { " – due \(name($0)) unchanged" } ?? ""
            return RowStatus(kind: .backFromSnooze, tooltip: "Back from snooze (was until \(was))\(due)")
        }
        return nil
    }
}
