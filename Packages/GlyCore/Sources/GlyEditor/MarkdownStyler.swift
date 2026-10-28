import Foundation
import GlyCore

/// How a link target should look (looked up by the editor, design P8).
public enum LinkAppearance: Equatable {
    /// `qualifier` tells same-titled targets apart ("person/alex"), link-disambiguation K2.
    case live(title: String, kind: LinkRef.Kind = .page, qualifier: String? = nil)
    case deleted(title: String, kind: LinkRef.Kind = .page)
    case missing

    var kind: LinkRef.Kind? {
        switch self { case .live(_, let k, _), .deleted(_, let k): k; case .missing: nil }
    }
    var qualifier: String? { if case .live(_, _, let q) = self { q } else { nil } }
}

extension LinkRef.Kind {
    /// SF Symbol shown before links of this kind.
    public var linkSymbol: String {
        switch self { case .page: "doc.text"; case .task: "checkmark.circle"; case .tag: "tag"; case .meeting: "calendar" }
    }
}

/// One styling decision over a UTF-16 range of the text. Pure data, so it can be tested without AppKit.
public struct StyleRun: Equatable {
    public enum Style: Equatable {
        case heading(Int)                 // whole line incl. marker
        case bold, italic
        case inlineCode
        case codeBlock                    // a line inside a fenced block (incl. fence lines)
        case syntax                       // markdown characters, shown dimmed
        case listItem(indent: Int)        // whole line; marker width in characters for the hanging indent
        case checkbox(checked: Bool)      // the `[ ]` / `[x]` characters
        case done                         // text of a checked checklist line
        case quote                        // whole line
        case chip(LinkAppearance, url: String)  // label of a gly link
        case hidden                       // collapsed `[` and `](gly://…)` of a glyash link
        case missingLink(title: String)   // title inside `[[…]]`
        case webLink(url: String)         // label of a web link or a bare URL
        // Live preview (live-preview L1): syntax off the caret lines.
        case bullet                       // a list marker drawn as a bullet (keeps its width)
        case quoteBar                     // a quote marker drawn as a bar (keeps its width)
        case invisible                    // keeps its width, not drawn (the `- ` before a checkbox)
        case checkboxGlyph(checked: Bool) // the `[ ]` / `[x]` drawn as a box (keeps its width)
    }
    public let range: NSRange
    public let style: Style
    public init(_ range: NSRange, _ style: Style) { self.range = range; self.style = style }
}

/// Line-oriented markdown styling (headings, emphasis, code, lists, checklists, quotes, links). Never changes the text.
public enum MarkdownStyler {
    /// Live preview (specs/markdown-editing "Live preview", design L1): syntax on lines outside `revealed` is hidden or
    /// drawn as a bullet, bar or box; on revealed lines (caret, selection, source mode) it stays visible, including link syntax.
    public static func livePreview(_ runs: [StyleRun], text: String, revealed: [NSRange]) -> [StyleRun] {
        let ns = text as NSString
        func lineRange(_ r: NSRange) -> NSRange { ns.lineRange(for: NSRange(location: min(r.location, ns.length), length: 0)) }
        func isRevealed(_ line: NSRange) -> Bool {
            revealed.contains { NSIntersectionRange($0, line).length > 0 || NSLocationInRange($0.location, line)
                || ($0.location == NSMaxRange(line) && $0.location == ns.length) }
        }
        // Line kinds, by line start.
        var kinds: [Int: [StyleRun.Style]] = [:]
        for run in runs {
            switch run.style {
            case .listItem, .quote, .codeBlock, .checkbox: kinds[lineRange(run.range).location, default: []].append(run.style)
            default: break
            }
        }
        var out: [StyleRun] = []
        for run in runs {
            guard case .syntax = run.style else {
                if case .hidden = run.style, isRevealed(lineRange(run.range)) { out.append(StyleRun(run.range, .syntax)); continue }
                if case .checkbox(let checked) = run.style, !isRevealed(lineRange(run.range)) {
                    out.append(run); out.append(StyleRun(run.range, .checkboxGlyph(checked: checked))); continue
                }
                out.append(run); continue
            }
            let line = lineRange(run.range)
            if isRevealed(line) { out.append(run); continue }
            let lineKinds = kinds[line.location] ?? []
            let marker = ns.substring(with: run.range)
            let atLineStart = ns.substring(with: NSRange(location: line.location, length: run.range.location - line.location))
                .allSatisfy { $0 == " " || $0 == "\t" }
            if lineKinds.contains(where: { if case .checkbox = $0 { true } else { false } }), atLineStart {
                out.append(StyleRun(run.range, .invisible))
            } else if lineKinds.contains(where: { if case .listItem = $0 { true } else { false } }), atLineStart {
                // Bullets for -, *, +; numbers stay as written (no dimming).
                if ["-", "*", "+"].contains(marker) { out.append(StyleRun(run.range, .bullet)) }
            } else if lineKinds.contains(where: { if case .quote = $0 { true } else { false } }), atLineStart {
                out.append(StyleRun(run.range, .quoteBar))
            } else {
                out.append(StyleRun(run.range, .hidden))    // headings, emphasis, code ticks, fences, link brackets
            }
        }
        return out
    }

    static func re(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression { .constant(p, options: o) }
    static let heading = re(#"^(#{1,6})[ \t]+\S.*$"#)
    static let fence = re(#"^[ \t]*(```|~~~)"#)
    static let list = re(#"^([ \t]*)([-*+]|\d{1,3}[.)])[ \t]+"#)
    static let checkbox = re(#"^([ \t]*[-*+][ \t]+)(\[[ xX]\])(?=[ \t]|$)"#)
    static let quote = re(#"^[ \t]*>[ \t]?"#)
    static let bold = re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    static let italic = re(#"(?<![*_\w])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*_\w])"#)
    static let codeSpan = re(#"(`+)(?:(?!\1).)+?\1"#)
    static let webLink = re(#"\[((?:[^\[\]\n]|\[[^\[\]\n]*\])*)\]\(((?:https?|mailto|message):[^)\s]+)\)"#)
    static let detector: NSDataDetector = {
        do { return try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) } catch {
            preconditionFailure("link detector unavailable: \(error)")
        }
    }()

    // The line-by-line pass carries fence and list state across lines; splitting it would only thread that state around.
    /// - Parameter appearance: current title/state of a gly link target.
    public static func runs(for text: String, appearance: (ParsedLink.Target) -> LinkAppearance) -> [StyleRun] { // swiftlint:disable:this function_body_length
        let ns = text as NSString
        var runs: [StyleRun] = []
        var inFence = false
        var codeRanges: [NSRange] = []

        // Block structure, line by line.
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = ns.substring(with: lineRange)
            let local = NSRange(location: 0, length: (line as NSString).length)
            func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + lineRange.location, length: r.length) }

            if fence.firstMatch(in: line, range: local) != nil {
                runs.append(StyleRun(lineRange, .codeBlock)); runs.append(StyleRun(lineRange, .syntax))
                codeRanges.append(lineRange); inFence.toggle(); return
            }
            if inFence { runs.append(StyleRun(lineRange, .codeBlock)); codeRanges.append(lineRange); return }

            if let m = heading.firstMatch(in: line, range: local) {
                runs.append(StyleRun(lineRange, .heading(m.range(at: 1).length)))
                runs.append(StyleRun(shift(NSRange(location: 0, length: m.range(at: 1).length + 1)), .syntax))
            } else if let m = checkbox.firstMatch(in: line, range: local) {
                let marker = m.range(at: 1), box = m.range(at: 2)
                let checked = (line as NSString).substring(with: box).lowercased() == "[x]"
                runs.append(StyleRun(lineRange, .listItem(indent: NSMaxRange(box) + 1)))
                runs.append(StyleRun(shift(marker), .syntax))
                runs.append(StyleRun(shift(box), .checkbox(checked: checked)))
                if checked, NSMaxRange(box) < local.length {
                    runs.append(StyleRun(shift(NSRange(location: NSMaxRange(box), length: local.length - NSMaxRange(box))), .done))
                }
            } else if let m = list.firstMatch(in: line, range: local) {
                runs.append(StyleRun(lineRange, .listItem(indent: m.range.length)))
                runs.append(StyleRun(shift(m.range(at: 2)), .syntax))
            } else if let m = quote.firstMatch(in: line, range: local) {
                runs.append(StyleRun(lineRange, .quote))
                runs.append(StyleRun(shift(m.range), .syntax))
            }
        }

        // Inline: code spans first (nothing inside them is styled further).
        let full = NSRange(location: 0, length: ns.length)
        func inCode(_ r: NSRange) -> Bool { codeRanges.contains { NSIntersectionRange($0, r).length > 0 } }
        for m in codeSpan.matches(in: text, range: full) where !inCode(m.range) {
            runs.append(StyleRun(m.range, .inlineCode))
            let tick = m.range(at: 1).length
            runs.append(StyleRun(NSRange(location: m.range.location, length: tick), .syntax))
            runs.append(StyleRun(NSRange(location: NSMaxRange(m.range) - tick, length: tick), .syntax))
            codeRanges.append(m.range)
        }

        // gly links (the parser already skips code).
        var linkRanges: [NSRange] = []
        for link in LinkParser.links(in: text) {
            linkRanges.append(link.range)
            switch link.target {
            case .missing(let title):
                runs.append(StyleRun(NSRange(location: link.range.location, length: 2), .syntax))
                runs.append(StyleRun(NSRange(location: link.range.location + 2, length: link.range.length - 4), .missingLink(title: title)))
                runs.append(StyleRun(NSRange(location: NSMaxRange(link.range) - 2, length: 2), .syntax))
            case .item, .tag:
                let labelLength = (link.label as NSString).length
                let label = NSRange(location: link.range.location + 1, length: labelLength)
                let url = ns.substring(with: NSRange(location: NSMaxRange(label) + 2, length: NSMaxRange(link.range) - NSMaxRange(label) - 3))
                runs.append(StyleRun(NSRange(location: link.range.location, length: 1), .hidden))
                runs.append(StyleRun(label, .chip(appearance(link.target), url: url)))
                runs.append(StyleRun(NSRange(location: NSMaxRange(label), length: NSMaxRange(link.range) - NSMaxRange(label)), .hidden))
            }
        }
        func taken(_ r: NSRange) -> Bool { inCode(r) || linkRanges.contains { NSIntersectionRange($0, r).length > 0 } }

        // Web links: `[text](https://…)` with visible, dimmed syntax; bare URLs.
        for m in webLink.matches(in: text, range: full) where !taken(m.range) {
            let url = ns.substring(with: m.range(at: 2))
            runs.append(StyleRun(m.range(at: 1), .webLink(url: url)))
            runs.append(StyleRun(NSRange(location: m.range.location, length: 1), .syntax))
            runs.append(StyleRun(NSRange(location: NSMaxRange(m.range(at: 1)), length: NSMaxRange(m.range) - NSMaxRange(m.range(at: 1))), .syntax))
            linkRanges.append(m.range)
        }
        for m in detector.matches(in: text, range: full) where !taken(m.range) {
            guard let url = m.url, ["http", "https"].contains(url.scheme ?? "") else { continue }
            runs.append(StyleRun(m.range, .webLink(url: url.absoluteString)))
        }

        // Emphasis outside code and links.
        for m in bold.matches(in: text, range: full) where !taken(m.range) {
            let mark = m.range(at: 1).length
            runs.append(StyleRun(m.range(at: 2), .bold))
            runs.append(StyleRun(NSRange(location: m.range.location, length: mark), .syntax))
            runs.append(StyleRun(NSRange(location: NSMaxRange(m.range) - mark, length: mark), .syntax))
        }
        for m in italic.matches(in: text, range: full) where !taken(m.range) {
            runs.append(StyleRun(m.range(at: 2), .italic))
            runs.append(StyleRun(NSRange(location: m.range.location, length: 1), .syntax))
            runs.append(StyleRun(NSRange(location: NSMaxRange(m.range) - 1, length: 1), .syntax))
        }
        return runs
    }
}
