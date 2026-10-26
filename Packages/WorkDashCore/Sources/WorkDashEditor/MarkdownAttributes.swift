#if canImport(AppKit)
import AppKit

public extension NSAttributedString.Key {
    /// URL string of a link (WorkDash or web); used for ⌘-click.
    static let wdLink = NSAttributedString.Key("wdLink")
    /// A checklist box; value is whether it's checked.
    static let wdCheckbox = NSAttributedString.Key("wdCheckbox")
    /// A collapsed range the caret skips (WorkDash link syntax).
    static let wdHidden = NSAttributedString.Key("wdHidden")
}

/// Applies `StyleRun`s as fonts, colors and paragraph styles (design P8).
public enum MarkdownAttributes {
    public static var baseFont: NSFont { .systemFont(ofSize: NSFont.systemFontSize + 1) }

    public static func base() -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacing = 4
        return [.font: baseFont, .foregroundColor: NSColor.textColor, .paragraphStyle: p]
    }

    /// Resets `range` to the base style and applies the runs that intersect it.
    public static func apply(_ runs: [StyleRun], to text: NSMutableAttributedString, in range: NSRange? = nil) {
        let whole = range ?? NSRange(location: 0, length: text.length)
        text.setAttributes(base(), range: whole)
        let size = baseFont.pointSize
        // Line-level styles first, then inline, then syntax/hidden on top.
        let order: (StyleRun.Style) -> Int = { s in
            switch s {
            case .heading, .codeBlock, .listItem, .quote: return 0
            case .syntax, .hidden: return 2
            default: return 1
            }
        }
        for run in runs.sorted(by: { order($0.style) < order($1.style) }) {
            let r = NSIntersectionRange(run.range, whole)
            guard r.length > 0 || (run.range.length == 0 && whole.length == 0) else { continue }
            switch run.style {
            case .heading(let level):
                let scale: [CGFloat] = [1.6, 1.4, 1.25, 1.12, 1.05, 1.0]
                text.addAttribute(.font, value: NSFont.systemFont(ofSize: size * scale[min(level, 6) - 1], weight: .bold), range: r)
            case .bold:
                text.applyFontTraits(.boldFontMask, range: r)
            case .italic:
                text.applyFontTraits(.italicFontMask, range: r)
            case .inlineCode, .codeBlock:
                text.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular), range: r)
                text.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.25), range: r)
            case .syntax:
                text.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: r)
            case .listItem(let indent):
                let p = NSMutableParagraphStyle()
                p.paragraphSpacing = 2
                let width = (String(repeating: " ", count: indent) as NSString).size(withAttributes: [.font: baseFont]).width
                p.headIndent = width
                text.addAttribute(.paragraphStyle, value: p, range: r)
            case .checkbox(let checked):
                text.addAttribute(.wdCheckbox, value: checked, range: r)
                text.addAttribute(.foregroundColor, value: checked ? NSColor.controlAccentColor : NSColor.secondaryLabelColor, range: r)
                text.addAttribute(.cursor, value: NSCursor.pointingHand, range: r)
            case .done:
                text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
                text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
            case .quote:
                text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
                let p = NSMutableParagraphStyle(); p.headIndent = 12; p.firstLineHeadIndent = 0
                text.addAttribute(.paragraphStyle, value: p, range: r)
            case .chip(let appearance, let url):
                text.addAttribute(.wdLink, value: url, range: r)
                text.addAttribute(.cursor, value: NSCursor.pointingHand, range: r)
                switch appearance {
                case .live:
                    text.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: r)
                    text.addAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.12), range: r)
                case .deleted:
                    text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
                    text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
                    text.addAttribute(.toolTip, value: "link target deleted", range: r)
                case .missing:
                    text.addAttribute(.foregroundColor, value: NSColor.systemRed, range: r)
                }
            case .hidden:
                text.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: r)
                text.addAttribute(.foregroundColor, value: NSColor.clear, range: r)
                text.addAttribute(.wdHidden, value: true, range: r)
            case .missingLink(let title):
                text.addAttribute(.foregroundColor, value: NSColor.systemRed, range: r)
                text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue, range: r)
                text.addAttribute(.wdLink, value: "workdash://missing/" + (title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title), range: r)
                text.addAttribute(.toolTip, value: "Missing page – ⌘-click to create “\(title)”", range: r)
            case .webLink(let url):
                text.addAttribute(.foregroundColor, value: NSColor.linkColor, range: r)
                text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
                text.addAttribute(.wdLink, value: url, range: r)
                text.addAttribute(.toolTip, value: url, range: r)
            }
        }
    }
}
#endif
