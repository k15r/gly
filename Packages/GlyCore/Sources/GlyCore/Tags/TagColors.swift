import Foundation
import GRDB

/// The palette for tag colors (tag-colors C1). Stored by name in `tags.color`; the app maps names to system colors.
public enum TagColor: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, green, teal, blue, indigo, purple, pink, brown, gray

    /// The colors automatic tags cycle through, in the order chips used before colors could be chosen.
    static let automaticCycle: [TagColor] = [.blue, .purple, .teal, .orange, .pink, .green, .indigo, .brown]

    /// The automatic color of a top-level name (stable across launches; same hash as the earlier chip tint).
    public static func automatic(forRoot root: String) -> TagColor {
        let key = TagName.key(for: root)
        let hash = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return automaticCycle[hash % automaticCycle.count]
    }
}

/// Where a tag's effective color comes from.
public enum TagColorSource: Equatable {
    case own
    case inherited(from: String)    // the tag key that has the color
    case automatic
}

/// Effective tag colors (tag-colors C2): own → nearest tag above with a color → automatic from the top-level name.
public struct TagColors: Equatable, Sendable {
    /// Own colors by tag key.
    public let own: [String: TagColor]
    public init(own: [String: TagColor] = [:]) { self.own = own }

    public func effective(_ name: String) -> (color: TagColor, source: TagColorSource) {
        let segments = TagName.key(for: name).split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return (.gray, .automatic) }
        for depth in stride(from: segments.count, through: 1, by: -1) {
            let key = segments.prefix(depth).joined(separator: "/")
            if let color = own[key] { return (color, depth == segments.count ? .own : .inherited(from: key)) }
        }
        return (TagColor.automatic(forRoot: segments[0]), .automatic)
    }

    public func color(_ name: String) -> TagColor { effective(name).color }
}

extension TagQueries {
    /// Own colors of live tags; unknown stored names count as none.
    public static func colors(_ db: Database) throws -> TagColors {
        var own: [String: TagColor] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT name_key, color FROM live_tags WHERE color IS NOT NULL") {
            if let c = TagColor(rawValue: r["color"]) { own[r["name_key"]] = c }
        }
        return TagColors(own: own)
    }
}
