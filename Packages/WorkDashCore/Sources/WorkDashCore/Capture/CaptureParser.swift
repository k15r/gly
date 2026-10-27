import Foundation

/// What the capture panel creates (specs/quick-capture "Capture panel").
public enum CaptureKind: String, Codable, CaseIterable { case task, page }

/// Typed capture text, read as title, tags, due date and priority (quick-capture Q1).
public struct CaptureDraft: Equatable {
    public var kind: CaptureKind
    public var title: String
    public var tags: [String]
    public var due: LocalDay?
    public var priority: Priority

    public var isEmpty: Bool { title.isEmpty }

    public var taskDraft: TaskDraft {
        TaskDraft(title: title, priority: priority, due: due.map { Due(day: $0.description) }, tags: tags)
    }
    public var pageDraft: PageDraft { PageDraft(title: title, tags: tags) }

    /// "Task · Call venue · due Wed 28 Oct · project/atlas · high"
    public func preview(today: LocalDay) -> String {
        var parts = [kind == .task ? "Task" : "Page", title.isEmpty ? "(no title)" : title]
        if let due { parts.append("due " + NotesSections.heading(for: due, today: today).dropFirst(3)) }
        parts += tags
        if priority != .none { parts.append(priority.rawValue) }
        return parts.joined(separator: " · ")
    }
}

public enum CaptureParser {
    static let weekdays: [(names: [String], weekday: Int)] = [
        (["sunday", "sun"], 1), (["monday", "mon"], 2), (["tuesday", "tue", "tues"], 3), (["wednesday", "wed"], 4),
        (["thursday", "thu", "thur", "thurs"], 5), (["friday", "fri"], 6), (["saturday", "sat"], 7),
    ]
    static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// Tags (`#a/b`) and priority (`!`, `!!`) anywhere; for tasks, a due date (`today`, `tomorrow`, weekday, `3 Nov`,
    /// `2026-11-03`) only at the end of the remaining words, so date-like words inside a title stay in it.
    public static func parse(_ text: String, kind: CaptureKind, today: LocalDay, calendar: Calendar = .current) -> CaptureDraft {
        var words: [String] = []
        var tags: [String] = []
        var priority: Priority = .none
        for token in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            if token.hasPrefix("#"), token.count > 1, let tag = try? TagName(String(token.dropFirst())) {
                if !tags.contains(where: { TagName.key(for: $0) == tag.key }) { tags.append(tag.display) }
            } else if token == "!" {
                priority = .high
            } else if token == "!!" {
                priority = .urgent
            } else {
                words.append(token)
            }
        }
        var due: LocalDay?
        if kind == .task {
            if words.count >= 2, let d = dayMonth(words[words.count - 2], words[words.count - 1], today: today) {
                due = d; words.removeLast(2)
            } else if let last = words.last, let d = singleWord(last, today: today, calendar: calendar) {
                due = d; words.removeLast()
            }
        }
        return CaptureDraft(kind: kind, title: words.joined(separator: " "), tags: tags,
                            due: due, priority: kind == .task ? priority : .none)
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
