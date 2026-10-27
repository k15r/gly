import Foundation

/// A validated, normalized tag name such as `person/alex` or `project/atlas/logs` (specs/tags "Tag names").
public struct TagName: Hashable, CustomStringConvertible {
    /// Display form, casing as entered.
    public let display: String
    /// Case-folded identity used for uniqueness, lookup and filtering.
    public let key: String

    public var segments: [Substring] { display.split(separator: "/") }
    public var description: String { display }

    public enum Invalid: Error, Equatable, CustomStringConvertible {
        case empty
        case emptySegment(String)
        public var description: String {
            switch self {
            case .empty: return "Tag names must not be empty."
            case .emptySegment(let raw): return "“\(raw)”: tag segments must not be empty (no “//”)."
            }
        }
    }

    public init(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Invalid.empty }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw Invalid.emptySegment(raw) }
        display = parts.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "/")
        key = TagName.key(for: display)
    }

    /// Case folding independent of the user's locale, so `Person/Alex` and `person/alex` collide.
    public static func key(for name: String) -> String {
        name.folding(options: [.caseInsensitive], locale: nil)
    }
}
