import Foundation
import GlyCore

/// One entry of the menu a link opens when it has no live target (trash-bin T5).
public enum LinkMenuEntry: Equatable {
    /// Replaces the link in the text with `insert` (a candidate, a same-titled item).
    case replace(LinkSuggestion)
    /// Opens a URL through the app (new page/task, restore, show in trash).
    case open(title: String, symbol: String, url: URL)
    /// A disabled line with context (e.g. "deleted 2 h ago by Claude Code").
    case info(String)
}

/// The link menu: sections of entries, shown with separators between non-empty sections.
public struct LinkMenuModel: Equatable {
    public var sections: [[LinkMenuEntry]]
    public init(_ sections: [[LinkMenuEntry]]) { self.sections = sections }

    /// A typed link without target: its candidates (if ambiguous, link-disambiguation K5), then new page / new task.
    public static func missing(typed: String, candidates: [LinkSuggestion]) -> LinkMenuModel {
        let create: [LinkMenuEntry] = [LinkRef.Kind.page, .task].compactMap { kind in
            guard let label = MarkdownBlocks.createLabel(typed, kind: kind),
                  let url = URL(string: LinkParser.missingURL(typed, create: kind)) else { return nil }
            return .open(title: label, symbol: kind.linkSymbol, url: url)
        }
        return LinkMenuModel([candidates.map { .replace($0) }, create])
    }

    /// The same menu without entries that edit the text (for read-only text).
    public var withoutReplacements: LinkMenuModel {
        LinkMenuModel(sections.map { $0.filter { if case .replace = $0 { false } else { true } } })
    }

    /// The default for editors without an app-provided menu: missing links can still be created.
    public static func standard(_ target: ParsedLink.Target) -> LinkMenuModel? {
        if case .missing(let typed) = target { return .missing(typed: typed, candidates: []) }
        return nil
    }
}

extension ParsedLink.Target {
    /// The target a gly link URL points to (`gly://item|tag/<id>`, `gly://missing/<text>`).
    public init?(url: URL) {
        guard LinkParser.isOwn(url) else { return nil }
        switch url.host {
        case "item": self = .item(url.lastPathComponent.uppercased())
        case "tag": self = .tag(url.lastPathComponent.uppercased())
        case "missing": guard let typed = LinkParser.missingText(url) else { return nil }; self = .missing(typed)
        default: return nil
        }
    }

    /// Same target; ids compare case-insensitively.
    func matches(_ other: ParsedLink.Target) -> Bool {
        switch (self, other) {
        case (.item(let a), .item(let b)), (.tag(let a), .tag(let b)): return a.caseInsensitiveCompare(b) == .orderedSame
        case (.missing(let a), .missing(let b)): return a == b
        default: return false
        }
    }
}
