import Foundation

/// Daily working-hours window in minutes after midnight (same for every day, specs/daily-planning "Working hours").
public struct WorkingHours: Equatable, Codable {
    public var startMinute: Int
    public var endMinute: Int
    public init(startMinute: Int = 9 * 60, endMinute: Int = 17 * 60) { self.startMinute = startMinute; self.endMinute = endMinute }
    public var minutesPerDay: Int { max(0, endMinute - startMinute) }

    /// The window on a given local day (DST-safe: built from the day's wall-clock times).
    public func window(on day: LocalDay, calendar: Calendar = .current) -> DateInterval? {
        let start = day.interval(in: calendar).start
        guard let s = calendar.date(byAdding: .minute, value: startMinute, to: start),
              let e = calendar.date(byAdding: .minute, value: endMinute, to: start), e > s else { return nil }
        // Use wall-clock hours so a DST change during the night doesn't shift the window.
        let sh = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: start) ?? s
        let eh = calendar.date(bySettingHour: endMinute / 60 % 24, minute: endMinute % 60, second: 0, of: start) ?? e
        return eh > sh ? DateInterval(start: sh, end: eh) : DateInterval(start: s, end: e)
    }
}

/// Free time between two moments (specs/daily-planning "Free time", design Q6).
public enum FreeTime {
    /// Working time in `[from, to]` minus the union of blocking intervals minus half of the maybe-only intervals.
    public static func minutes(from: Date, to: Date, busy: [(interval: DateInterval, weight: BlockingWeight)],
                               hours: WorkingHours, calendar: Calendar = .current) -> Double {
        guard to > from else { return 0 }
        var total = 0.0
        var day = LocalDay(date: from, calendar: calendar)
        let lastDay = LocalDay(date: to.addingTimeInterval(-1), calendar: calendar)
        while day <= lastDay {
            if let window = hours.window(on: day, calendar: calendar),
               let part = intersection(window, DateInterval(start: from, end: to)) {
                let blocking = union(busy.filter { $0.weight == .blocks }.compactMap { intersection($0.interval, part) })
                let maybe = union(busy.filter { $0.weight == .maybe }.compactMap { intersection($0.interval, part) })
                let maybeOnly = subtract(maybe, blocking)
                total += part.duration - length(blocking) - 0.5 * length(maybeOnly)
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return max(0, total / 60)
    }

    static func intersection(_ a: DateInterval, _ b: DateInterval) -> DateInterval? {
        let s = max(a.start, b.start), e = min(a.end, b.end)
        return e > s ? DateInterval(start: s, end: e) : nil
    }

    /// Merges overlapping intervals.
    static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for i in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, i.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, i.end))
            } else {
                result.append(i)
            }
        }
        return result
    }

    /// Parts of `a` (merged) not covered by `b` (merged).
    static func subtract(_ a: [DateInterval], _ b: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for i in a {
            var pieces = [i]
            for cut in b {
                pieces = pieces.flatMap { p -> [DateInterval] in
                    guard intersection(p, cut) != nil else { return [p] }
                    var out: [DateInterval] = []
                    if cut.start > p.start { out.append(DateInterval(start: p.start, end: cut.start)) }
                    if cut.end < p.end { out.append(DateInterval(start: cut.end, end: p.end)) }
                    return out
                }
            }
            result += pieces
        }
        return result
    }

    static func length(_ intervals: [DateInterval]) -> TimeInterval { intervals.reduce(0) { $0 + $1.duration } }
}
