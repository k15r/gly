import Foundation

/// A floating calendar day (YYYY-MM-DD) without time zone, plus helpers to map it to the local calendar.
public struct LocalDay: Hashable, Comparable, CustomStringConvertible, Codable {
    public let year: Int, month: Int, day: Int

    public init?(_ string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d
        let cal = Calendar(identifier: .gregorian)
        guard comps.isValidDate(in: cal) else { return nil }
        year = y; month = m; day = d
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        year = c.year!; month = c.month!; day = c.day!
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Start and end of this day in `calendar`'s time zone (DST-safe: a day may be 23 or 25 hours).
    public func interval(in calendar: Calendar = .current) -> DateInterval {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = day
        let start = calendar.startOfDay(for: calendar.date(from: comps)!)
        return calendar.dateInterval(of: .day, for: start)!
    }

    public func adding(days: Int, calendar: Calendar = .current) -> LocalDay {
        LocalDay(date: calendar.date(byAdding: .day, value: days, to: interval(in: calendar).start)!, calendar: calendar)
    }

    public static func < (a: LocalDay, b: LocalDay) -> Bool { a.description < b.description }
}
