import Foundation

/// Date words as people type them, shared by quick capture and the due date popover (task-properties T3):
/// `today`, `tomorrow`, a weekday (`fri`, `friday`), `3 nov` / `3. November`, `2026-11-03`, each optionally followed by a time.
public enum DateWords {
    static let weekdays: [(names: [String], weekday: Int)] = [
        (["sunday", "sun"], 1), (["monday", "mon"], 2), (["tuesday", "tue", "tues"], 3), (["wednesday", "wed"], 4),
        (["thursday", "thu", "thur", "thurs"], 5), (["friday", "fri"], 6), (["saturday", "sat"], 7),
    ]
    static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// A whole input like "fri", "tomorrow 9:30" or "3 nov 14:00": the day and an optional time (HH:mm); nil if it isn't a date.
    public static func parse(_ text: String, today: LocalDay, calendar: Calendar = .current) -> (day: LocalDay, time: String?)? {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var time: String?
        if let last = words.last, let t = Self.time(last) { time = t; words.removeLast() }
        let day: LocalDay?
        switch words.count {
        case 1: day = singleWord(words[0], today: today, calendar: calendar)
        case 2: day = dayMonth(words[0], words[1], today: today)
        default: day = nil
        }
        return day.map { ($0, time) }
    }

    /// `9:30`, `14:00` → "09:30", "14:00"; nil otherwise.
    static func time(_ word: String) -> String? {
        let parts = word.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m),
              parts[1].count == 2 else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    static func singleWord(_ word: String, today: LocalDay, calendar: Calendar) -> LocalDay? {
        let w = word.lowercased()
        if w == "today" { return today }
        if w == "tomorrow" { return today.adding(days: 1, calendar: calendar) }
        if let iso = LocalDay(w) { return iso }
        guard let target = weekdays.first(where: { $0.names.contains(w) })?.weekday else { return nil }
        let current = calendar.component(.weekday, from: today.interval(in: calendar).start)
        let ahead = (target - current + 7) % 7
        return today.adding(days: ahead == 0 ? 7 : ahead, calendar: calendar)   // today's weekday = a week ahead
    }

    /// `3 Nov` / `3. Nov` / `3 November`: this year, or next year if that day has passed.
    static func dayMonth(_ dayWord: String, _ monthWord: String, today: LocalDay) -> LocalDay? {
        guard let day = Int(dayWord.trimmingCharacters(in: CharacterSet(charactersIn: "."))), (1...31).contains(day),
              let month = months.firstIndex(where: { monthWord.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")).hasPrefix($0) })
                .map({ $0 + 1 }), monthWord.count >= 3 else { return nil }
        for year in [today.year, today.year + 1] {
            if let d = LocalDay(String(format: "%04d-%02d-%02d", year, month, day)), !(d < today) { return d }
        }
        return nil
    }
}
