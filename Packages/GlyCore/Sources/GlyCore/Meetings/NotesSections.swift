import Foundation

/// Dated sections in a meeting's notes (meeting-pages N3): `## Tue 3 Nov` (plus the year when it isn't the current
/// year), newest on top. Fixed English format, so parsing doesn't depend on the system language.
public enum NotesSections {
    public struct Section: Equatable {
        public let day: LocalDay
        /// Range of the whole section (heading through the line before the next heading of any section).
        public let range: NSRange
        /// Where text of the section starts (after the heading line).
        public let contentStart: Int
    }

    static let headingRE = try! NSRegularExpression(pattern: #"^## (Mon|Tue|Wed|Thu|Fri|Sat|Sun) (\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)(?: (\d{4}))?[ \t]*$"#,
                                                   options: [.anchorsMatchLines])
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// The heading for a day; the year is added when it differs from `today`'s.
    public static func heading(for day: LocalDay, today: LocalDay) -> String {
        var comps = DateComponents(); comps.year = day.year; comps.month = day.month; comps.day = day.day
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.date(from: comps).map { cal.component(.weekday, from: $0) } ?? 1
        let name = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday - 1]
        return "## \(name) \(day.day) \(months[day.month - 1])" + (day.year == today.year ? "" : " \(day.year)")
    }

    /// Dated sections in document order. A heading without a year belongs to `today`'s year, or the year before
    /// if that would put it more than six months in the future.
    public static func sections(in body: String, today: LocalDay) -> [Section] {
        let ns = body as NSString
        let matches = headingRE.matches(in: body, range: NSRange(location: 0, length: ns.length))
        var result: [Section] = []
        for (i, m) in matches.enumerated() {
            let dayNumber = Int(ns.substring(with: m.range(at: 2)))!
            let month = months.firstIndex(of: ns.substring(with: m.range(at: 3)))! + 1
            var year = m.range(at: 4).location == NSNotFound ? today.year : Int(ns.substring(with: m.range(at: 4)))!
            if m.range(at: 4).location == NSNotFound, month - today.month > 6 { year -= 1 }
            guard let day = LocalDay(String(format: "%04d-%02d-%02d", year, month, dayNumber)) else { continue }
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let lineEnd = NSMaxRange(ns.lineRange(for: m.range))
            result.append(Section(day: day, range: NSRange(location: m.range.location, length: end - m.range.location), contentStart: min(lineEnd, end)))
        }
        return result
    }

    /// The section for a day, if the document has one.
    public static func section(for day: LocalDay, in body: String, today: LocalDay) -> Section? {
        sections(in: body, today: today).first { $0.day == day }
    }

    /// `body` with `text` added to the day's section: appended if it exists, else in a new section placed above the
    /// first older section (newest on top), or at the end.
    public static func insert(_ text: String, for day: LocalDay, into body: String, today: LocalDay) -> String {
        let addition = text.trimmingCharacters(in: .newlines)
        let ns = body as NSString
        let all = sections(in: body, today: today)
        if let existing = all.first(where: { $0.day == day }) {
            let sectionText = ns.substring(with: existing.range)
            let trimmed = sectionText.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            let trailing = String(sectionText.dropFirst(trimmed.count))
            let replacement = trimmed + "\n" + addition + (trailing.contains("\n\n") || NSMaxRange(existing.range) < ns.length ? "\n\n" : "\n")
            return ns.replacingCharacters(in: existing.range, with: replacement)
        }
        let newSection = heading(for: day, today: today) + "\n" + addition + "\n"
        if let older = all.first(where: { $0.day < day }) {
            return ns.replacingCharacters(in: NSRange(location: older.range.location, length: 0), with: newSection + "\n")
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return newSection }
        return body.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) + "\n\n" + newSection
    }
}
