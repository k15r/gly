import Foundation

public enum TaskStatus: String, Codable, CaseIterable {
    case open, snoozed, done, dropped
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
