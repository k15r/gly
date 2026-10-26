import Foundation
import SwiftUI
import WorkDashCore

/// A block of markdown for the read view.
public enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(indent: Int, marker: String, text: String)
    /// `line`: index of the source line, for toggling.
    case checklistItem(indent: Int, checked: Bool, text: String, line: Int)
    case quote(String)
    case code(String)
    case blank
}

public enum MarkdownBlocks {
    /// Capture groups of the first match of `pattern` in `s`, or nil.
    static func groups(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { return nil }
        return (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : (s as NSString).substring(with: m.range(at: $0)) }
    }

    /// Splits markdown into blocks (one per line, fenced code as one block, consecutive text lines as one paragraph).
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var code: [String]? = nil
        var paragraph: [String] = []
        func flush() { if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] } }
        for (lineIndex, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let c = code { blocks.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(line); continue }
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
            if trimmed.isEmpty { flush(); blocks.append(.blank); continue }
            if let m = groups(#"^(#{1,6})\s+(.*)$"#, trimmed) {
                flush(); blocks.append(.heading(level: m[0].count, text: m[1])); continue
            }
            if let m = groups(#"^[-*+]\s+\[([ xX])\]\s?(.*)$"#, trimmed) {
                flush(); blocks.append(.checklistItem(indent: indent, checked: m[0] != " ", text: m[1], line: lineIndex)); continue
            }
            if let m = groups(#"^([-*+]|\d{1,3}[.)])\s+(.*)$"#, trimmed) {
                flush(); blocks.append(.listItem(indent: indent, marker: m[0], text: m[1])); continue
            }
            if let m = groups(#"^>\s?(.*)$"#, trimmed) {
                flush(); blocks.append(.quote(m[0])); continue
            }
            paragraph.append(line)
        }
        if let c = code { blocks.append(.code(c.joined(separator: "\n"))) }
        flush()
        // Collapse runs of blank lines.
        return blocks.enumerated().filter { i, b in !(b == .blank && (i == 0 || blocks[i - 1] == .blank)) }.map(\.1)
    }

    /// The text with the first `[[typed]]` replaced by `insert` (a canonical link).
    public static func pin(_ text: String, typed: String, with insert: String) -> String {
        guard let link = LinkParser.links(in: text).first(where: { $0.target == .missing(typed) }) else { return text }
        return (text as NSString).replacingCharacters(in: link.range, with: insert)
    }

    /// The text with the checklist box on `line` toggled (`[ ]` ↔ `[x]`); unchanged if that line isn't a checklist item.
    public static func toggleChecklist(_ text: String, line: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line),
              let re = try? NSRegularExpression(pattern: #"^([ \t]*[-*+][ \t]+)\[([ xX])\]"#),
              let m = re.firstMatch(in: lines[line], range: NSRange(location: 0, length: (lines[line] as NSString).length)) else { return text }
        let ns = lines[line] as NSString
        let box = m.range(at: 2)
        lines[line] = ns.replacingCharacters(in: box, with: ns.substring(with: box) == " " ? "x" : " ")
        return lines.joined(separator: "\n")
    }

    /// Inline markdown → AttributedString; `[[X]]` becomes a `workdash://missing/X` link; WorkDash links get their
    /// current appearance (deleted ones struck through, missing ones red).
    public static func inline(_ text: String, appearance: (ParsedLink.Target) -> LinkAppearance) -> AttributedString {
        let ns = NSMutableString(string: text)
        for link in LinkParser.links(in: text).reversed() {
            if case .missing(let title) = link.target {
                ns.replaceCharacters(in: link.range, with: "[\(title)](\(LinkParser.missingURL(title)))")
            }
        }
        var attributed = (try? AttributedString(markdown: ns as String, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(ns as String)
        // Collect first, then edit from the end, so earlier ranges stay valid.
        var titleReplacements: [(Range<AttributedString.Index>, String, URL)] = []
        for run in attributed.runs {
            guard let url = run.link, url.scheme == LinkParser.scheme else { continue }
            let range = run.range
            switch url.host {
            case "missing":
                attributed[range].foregroundColor = .red
            case "item", "tag":
                let id = url.lastPathComponent.uppercased()
                let target: ParsedLink.Target = url.host == "tag" ? .tag(id) : .item(id)
                switch appearance(target) {
                case .live(let title, _, _):
                    if String(attributed[range].characters) != title { titleReplacements.append((range, title, url)) }
                case .deleted:
                    attributed[range].strikethroughStyle = .single
                    attributed[range].foregroundColor = .secondary
                case .missing:
                    attributed[range].foregroundColor = .red
                }
            default: break
            }
        }
        for (range, title, url) in titleReplacements.reversed() {
            var replacement = AttributedString(title)
            replacement.link = url
            attributed.replaceSubrange(range, with: replacement)
        }
        return attributed
    }
}

extension MarkdownBlocks {
    /// Inline markdown as `Text`, with a kind icon before WorkDash and web links and the duplicate qualifier after
    /// WorkDash links (link-disambiguation K3). Display only; the source text is untouched.
    public static func inlineText(_ text: String, appearance: (ParsedLink.Target) -> LinkAppearance) -> Text {
        let attributed = inline(text, appearance: appearance)
        var result = Text("")
        var lastLink: URL?
        for run in attributed.runs {
            let piece = Text(AttributedString(attributed[run.range]))
            guard let url = run.link, url != lastLink else {
                result = result + piece
                if run.link == nil { lastLink = nil }
                continue
            }
            lastLink = url
            var qualifier: String?
            if url.scheme == LinkParser.scheme, let host = url.host, host == "item" || host == "tag" {
                let id = url.lastPathComponent.uppercased()
                let a = appearance(host == "tag" ? .tag(id) : .item(id))
                if let kind = a.kind { result = result + Text(Image(systemName: kind.linkSymbol)).foregroundColor(.secondary) + Text(" ") }
                qualifier = a.qualifier
            } else if ["http", "https", "mailto", "message"].contains(url.scheme ?? "") {
                result = result + Text(Image(systemName: "globe")).foregroundColor(.secondary) + Text(" ")
            }
            result = result + piece
            if let qualifier { result = result + Text(" · " + qualifier).font(.caption).foregroundColor(.secondary) }
        }
        return result
    }
}

/// Rendered markdown (design P8). Links open through the environment's `openURL` (set by the app).
public struct MarkdownReadView: View {
    let text: String
    let appearance: (ParsedLink.Target) -> LinkAppearance
    /// Called with the new text when a checkbox is clicked or an ambiguous link is pinned; nil = read-only.
    let onChange: ((String) -> Void)?
    /// Targets an ambiguous typed link could mean (link-disambiguation K5).
    let candidates: (String) -> [LinkSuggestion]
    @Environment(\.openURL) private var openURL
    @State private var choosing: (typed: String, options: [LinkSuggestion], url: URL)?

    public init(text: String, appearance: @escaping (ParsedLink.Target) -> LinkAppearance, onChange: ((String) -> Void)? = nil,
                candidates: @escaping (String) -> [LinkSuggestion] = { _ in [] }) {
        self.text = text; self.appearance = appearance; self.onChange = onChange; self.candidates = candidates
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A missing link with candidates asks which one is meant before anything is created.
        .environment(\.openURL, OpenURLAction { url in
            if let typed = LinkParser.missingText(url), onChange != nil {
                let options = candidates(typed)
                if !options.isEmpty { choosing = (typed, options, url); return .handled }
            }
            openURL(url)
            return .handled
        })
        .confirmationDialog("Which “\(choosing?.typed ?? "")” do you mean?",
                            isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } })) {
            if let c = choosing {
                ForEach(c.options) { o in
                    Button(o.subtitle.isEmpty ? o.title : "\(o.title) – \(o.subtitle)") {
                        onChange?(MarkdownBlocks.pin(text, typed: c.typed, with: o.insert))
                    }
                }
                Button("Create page “\(c.typed)”") { openURL(c.url) }
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let t):
            inline(t).font([.title, .title2, .title3, .headline, .headline, .subheadline][min(level, 6) - 1]).bold()
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let t):
            inline(t)
        case .listItem(let indent, let marker, let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker.first?.isNumber == true ? marker : "•").foregroundStyle(.secondary)
                inline(t)
            }.padding(.leading, CGFloat(indent) * 16)
        case .checklistItem(let indent, let checked, let t, let line):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: checked ? "checkmark.square.fill" : "square").foregroundStyle(checked ? Color.accentColor : .secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { onChange?(MarkdownBlocks.toggleChecklist(text, line: line)) }
                    .help(onChange == nil ? "" : (checked ? "Mark as not done" : "Mark as done"))
                inline(t).strikethrough(checked).foregroundStyle(checked ? .secondary : .primary)
            }.padding(.leading, CGFloat(indent) * 16)
        case .quote(let t):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(.tertiary).frame(width: 3)
                inline(t).foregroundStyle(.secondary)
            }
        case .code(let t):
            Text(t).font(.system(.body, design: .monospaced)).padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        case .blank:
            Spacer().frame(height: 2)
        }
    }

    private func inline(_ t: String) -> Text { MarkdownBlocks.inlineText(t, appearance: appearance) }
}
