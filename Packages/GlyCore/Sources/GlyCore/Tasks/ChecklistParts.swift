import Foundation

/// An estimate at the end of a checklist item: an effort size or a duration (subtasks S1).
public enum PartEstimate: Equatable, Sendable {
    case size(Effort)
    /// Days are working days; resolved with the working-day length.
    case duration(days: Int, minutes: Int)

    public func minutes(sizes: EffortSizes, dayMinutes: Int) -> Int {
        switch self {
        case .size(let effort): sizes[effort]
        case .duration(let days, let minutes): days * dayMinutes + minutes
        }
    }
}

/// One part of a task: a checklist item of its notes (specs/tasks "Parts of a task").
public struct TaskPart: Equatable, Sendable {
    public let title: String
    public let estimate: PartEstimate?
    public let done: Bool
    public init(title: String, estimate: PartEstimate? = nil, done: Bool = false) {
        self.title = title; self.estimate = estimate; self.done = done
    }
}

/// Reads the parts of a task from its notes: `- [ ]` / `- [x]` lines outside fenced code, in text order,
/// each with an optional trailing estimate `(S)`, `(2h)`, `(1d 4h)`, `(30m)` (subtasks S1).
public enum ChecklistParts {
    static let item = NSRegularExpression.constant(#"^[ \t]*[-*+][ \t]+\[( |x|X)\][ \t]+(.*?)[ \t]*$"#)
    static let fence = NSRegularExpression.constant(#"^[ \t]*(```|~~~)"#)
    static let size = NSRegularExpression.constant(#"\((XS|S|M|L|XL)\)$"#)
    static let duration = NSRegularExpression.constant(#"\((?:(\d+)d)?[ \t]*(?:(\d+)h)?[ \t]*(?:(\d+)m)?\)$"#)

    public static func parse(_ notes: String) -> [TaskPart] {
        var parts: [TaskPart] = []
        var inFence = false
        for line in notes.components(separatedBy: "\n") {
            let ns = line as NSString, whole = NSRange(location: 0, length: ns.length)
            if fence.firstMatch(in: line, range: whole) != nil { inFence.toggle(); continue }
            guard !inFence, let m = item.firstMatch(in: line, range: whole) else { continue }
            let done = ns.substring(with: m.range(at: 1)) != " "
            let (title, estimate) = split(ns.substring(with: m.range(at: 2)))
            guard !title.isEmpty else { continue }
            parts.append(TaskPart(title: title, estimate: estimate, done: done))
        }
        return parts
    }

    /// The text without a trailing estimate, and the estimate; parentheses that aren't an estimate stay in the title.
    static func split(_ text: String) -> (String, PartEstimate?) {
        let ns = text as NSString, whole = NSRange(location: 0, length: ns.length)
        func title(before range: NSRange) -> String { ns.substring(to: range.location).trimmingCharacters(in: .whitespaces) }
        if let m = size.firstMatch(in: text, range: whole), let effort = Effort(rawValue: ns.substring(with: m.range(at: 1))) {
            return (title(before: m.range), .size(effort))
        }
        if let m = duration.firstMatch(in: text, range: whole) {
            func number(_ i: Int) -> Int? { m.range(at: i).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: i))) }
            let (d, h, min) = (number(1), number(2), number(3))
            if d != nil || h != nil || min != nil {
                return (title(before: m.range), .duration(days: d ?? 0, minutes: (h ?? 0) * 60 + (min ?? 0)))
            }
        }
        return (text, nil)
    }
}
