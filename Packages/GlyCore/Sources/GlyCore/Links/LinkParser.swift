import Foundation

/// A link found in markdown text (info-pages-and-links design P1).
public struct ParsedLink: Equatable {
    public enum Target: Equatable {
        case item(String)
        case tag(String)
        /// `[[Title]]` that didn't resolve (yet).
        case missing(String)
    }
    public let target: Target
    /// Shown text: the label of a canonical link, the title of a missing one.
    public let label: String
    /// Range of the whole link syntax in the text (UTF-16, as NSString/NSTextView use).
    public let range: NSRange
}

/// Finds gly links in markdown. Canonical: `[label](gly://item/<uuid>)` / `gly://tag/<uuid>`; the old
/// `workdash://` scheme is read the same way (rename-to-gly R4). Missing: `[[Title]]`. Links inside code spans and
/// fenced code blocks don't count; web links are ignored.
public enum LinkParser {
    /// The scheme links are written with.
    public static let scheme = "gly"
    /// Schemes still read as links (texts from before the rename, pasted links).
    public static let legacySchemes = ["workdash"]

    /// Whether a URL is one of ours (current or legacy scheme).
    public static func isOwn(_ url: URL) -> Bool {
        guard let s = url.scheme?.lowercased() else { return false }
        return s == scheme || legacySchemes.contains(s)
    }

    static let canonical = NSRegularExpression.constant(
        #"\[((?:[^\[\]\n]|\[[^\[\]\n]*\])*)\]\((?:gly|workdash)://(item|tag)/([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\)"#)
    static let missing = NSRegularExpression.constant(#"\[\[([^\[\]\n]+?)\]\]"#)
    static let fence = NSRegularExpression.constant(#"^[ \t]*(```|~~~).*$"#, options: [.anchorsMatchLines])
    static let codeSpan = NSRegularExpression.constant(#"(`+)(?:(?!\1).)+?\1"#)

    public static func links(in text: String) -> [ParsedLink] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let excluded = codeRanges(in: text)
        func isExcluded(_ r: NSRange) -> Bool { excluded.contains { NSIntersectionRange($0, r).length > 0 } }

        var result: [ParsedLink] = []
        for m in canonical.matches(in: text, range: full) where !isExcluded(m.range) {
            let label = ns.substring(with: m.range(at: 1))
            let id = ns.substring(with: m.range(at: 3)).uppercased()
            let target: ParsedLink.Target = ns.substring(with: m.range(at: 2)) == "tag" ? .tag(id) : .item(id)
            result.append(ParsedLink(target: target, label: label, range: m.range))
        }
        for m in missing.matches(in: text, range: full) where !isExcluded(m.range) {
            let title = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, !result.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }) else { continue }
            result.append(ParsedLink(target: .missing(title), label: title, range: m.range))
        }
        return result.sorted { $0.range.location < $1.range.location }
    }

    /// Ranges of fenced code blocks (from an opening fence line to the closing one, or to the end) and code spans.
    public static func codeRanges(in text: String) -> [NSRange] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var ranges: [NSRange] = []
        let fences = fence.matches(in: text, range: full)
        var i = 0
        while i < fences.count {
            let start = fences[i].range.location
            let end = i + 1 < fences.count ? NSMaxRange(fences[i + 1].range) : ns.length
            ranges.append(NSRange(location: start, length: end - start))
            i += 2
        }
        for m in codeSpan.matches(in: text, range: full) where !ranges.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            ranges.append(m.range)
        }
        return ranges
    }

    static let webLink = NSRegularExpression.constant(#"\[((?:[^\[\]\n]|\[[^\[\]\n]*\])*)\]\((?:https?|mailto|message):[^)\s]+\)"#)

    /// Text for the search index and excerpts: own and web links replaced by their labels, so URLs and ids aren't indexed.
    public static func plainText(_ text: String) -> String {
        let ns = NSMutableString(string: text)
        for link in links(in: text).reversed() { ns.replaceCharacters(in: link.range, with: link.label) }
        let once = ns as String
        return webLink.stringByReplacingMatches(in: once, range: NSRange(location: 0, length: (once as NSString).length), withTemplate: "$1")
    }

    /// The URL a missing `[[typed]]` link opens. `/` is encoded too, so tag paths (`person/alex/Goals`) survive as one piece.
    /// `create` asks the app to create that kind (`?create=task`); without it a page is created.
    public static func missingURL(_ typed: String, create: LinkRef.Kind? = nil) -> String {
        var allowed = CharacterSet.urlPathAllowed; allowed.remove("/")
        return "\(scheme)://missing/" + (typed.addingPercentEncoding(withAllowedCharacters: allowed) ?? typed)
            + (create.map { "?create=\($0.rawValue)" } ?? "")
    }

    /// What a missing-link URL asks to create (page unless `?create=task`).
    public static func missingCreateKind(_ url: URL) -> LinkRef.Kind {
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "create" }?.value
        return value.flatMap(LinkRef.Kind.init(rawValue:)) ?? .page
    }

    /// The typed text of a missing-link URL (the whole path, not just its last segment).
    public static func missingText(_ url: URL) -> String? {
        guard isOwn(url), url.host == "missing" else { return nil }
        let text = String(url.path(percentEncoded: false).dropFirst())
        return text.isEmpty ? nil : text
    }

    /// Canonical markdown for a link.
    public static func canonical(label: String, item id: String) -> String { "[\(escapeLabel(label))](\(scheme)://item/\(id))" }
    public static func canonical(label: String, tag id: String) -> String { "[\(escapeLabel(label))](\(scheme)://tag/\(id))" }

    static func escapeLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
    }
}
