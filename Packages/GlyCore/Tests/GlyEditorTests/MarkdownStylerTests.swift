import AppKit
import XCTest
import GlyCore
@testable import GlyEditor

final class MarkdownStylerTests: XCTestCase {
    let id = "0E5A3C1D-2B4F-4A6E-9C8D-1F2E3D4C5B6A"
    func runs(_ text: String, appearance: LinkAppearance = .live(title: "T")) -> [StyleRun] {
        MarkdownStyler.runs(for: text) { _ in appearance }
    }
    func styles(_ text: String, at substring: String, appearance: LinkAppearance = .live(title: "T")) -> [StyleRun.Style] {
        let r = (text as NSString).range(of: substring)
        return runs(text, appearance: appearance).filter { $0.range == r }.map(\.style)
    }

    func testHeading() {
        let t = "## Decisions"
        XCTAssertTrue(runs(t).contains(StyleRun(NSRange(location: 0, length: 12), .heading(2))))
        XCTAssertEqual(styles(t, at: "## "), [.syntax])
    }

    func testEmphasis() {
        let t = "a **bold** and *it* and _it2_"
        XCTAssertEqual(styles(t, at: "bold"), [.bold])
        XCTAssertEqual(styles(t, at: "it"), [.italic])
        XCTAssertEqual(styles(t, at: "it2"), [.italic])
        XCTAssertFalse(runs("**bold**").contains { $0.style == .italic }, "bold markers aren't italic")
        XCTAssertFalse(runs("snake_case_name").contains { $0.style == .italic })
    }

    func testCode() {
        let t = "x `**not bold**` y\n```\n# not a heading\n**no**\n```\nafter"
        XCTAssertEqual(styles(t, at: "`**not bold**`"), [.inlineCode])
        XCTAssertFalse(runs(t).contains { $0.style == .bold })
        XCTAssertFalse(runs(t).contains { if case .heading = $0.style { return true }; return false })
        XCTAssertEqual(runs(t).filter { $0.style == .codeBlock }.count, 4, "fence lines and content lines")
    }

    func testListsChecklistsQuotes() {
        let t = "- item\n1. first\n- [ ] open\n- [x] done task\n> quoted"
        XCTAssertTrue(runs(t).contains { $0.style == .listItem(indent: 2) })
        XCTAssertTrue(runs(t).contains { $0.style == .listItem(indent: 3) })
        XCTAssertEqual(styles(t, at: "[ ]"), [.checkbox(checked: false)])
        XCTAssertEqual(styles(t, at: "[x]"), [.checkbox(checked: true)])
        XCTAssertEqual(styles(t, at: " done task"), [.done])
        XCTAssertTrue(runs(t).contains { $0.style == .quote })
    }

    func testGlyLinkChipAndHiddenSyntax() {
        let link = "[Atlas](gly://item/\(id))"
        let t = "see \(link)"
        let r = runs(t, appearance: .live(title: "Atlas"))
        XCTAssertTrue(r.contains(StyleRun(NSRange(location: 5, length: 5), .chip(.live(title: "Atlas"), url: "gly://item/\(id)"))))
        let hidden = r.filter { $0.style == .hidden }.map(\.range)
        XCTAssertEqual(hidden, [NSRange(location: 4, length: 1), NSRange(location: 10, length: (link as NSString).length - 6)])
    }

    func testMissingAndDeletedLinks() {
        let t = "[[Retro notes]]"
        XCTAssertEqual(styles(t, at: "Retro notes"), [.missingLink(title: "Retro notes")])
        let d = "[Old](gly://item/\(id))"
        XCTAssertEqual(styles(d, at: "Old", appearance: .deleted(title: "Old")), [.chip(.deleted(title: "Old"), url: "gly://item/\(id)")])
    }

    func testWebLinks() {
        let t = "[Design doc](https://example.com/doc) and https://example.com/report"
        XCTAssertEqual(styles(t, at: "Design doc"), [.webLink(url: "https://example.com/doc")])
        XCTAssertEqual(styles(t, at: "https://example.com/report"), [.webLink(url: "https://example.com/report")])
        XCTAssertEqual(styles(t, at: "](https://example.com/doc)"), [.syntax], "web link syntax stays visible, dimmed")
        XCTAssertFalse(runs(t).contains { $0.style == .hidden })
    }

    /// bookmarks B3: a bookmarked URL's link carries its bookmark, which picks the icon and the tooltip.
    func testBookmarkedWebLinks() {
        let t = "[Dashboard](https://grafana.example/d/latency) and [Other](https://other.example) https://grafana.example/d/latency"
        let mark = BookmarkMark(title: "Latency dashboard", description: "p99 by service", tags: ["project/atlas"])
        let lookup: (String) -> BookmarkMark? = { $0 == "https://grafana.example/d/latency" ? mark : nil }
        let all = MarkdownStyler.runs(for: t, appearance: { _ in .missing }, bookmark: lookup)
        func style(_ s: String) -> [StyleRun.Style] { let r = (t as NSString).range(of: s); return all.filter { $0.range == r }.map(\.style) }
        XCTAssertEqual(style("Dashboard"), [.webLink(url: "https://grafana.example/d/latency", bookmark: mark)])
        XCTAssertEqual(style("Other"), [.webLink(url: "https://other.example")])
        let bare = (t as NSString).range(of: "https://grafana.example/d/latency", options: .backwards)
        XCTAssertEqual(all.filter { $0.range == bare }.map(\.style), [.webLink(url: "https://grafana.example/d/latency", bookmark: mark)])
        XCTAssertEqual(mark.tooltip(url: "https://grafana.example/d/latency"),
                       "Latency dashboard\np99 by service\n#project/atlas\nhttps://grafana.example/d/latency")

        let text = NSMutableAttributedString(string: t)
        MarkdownAttributes.apply(all, to: text)
        let at = (t as NSString).range(of: "Dashboard").location, other = (t as NSString).range(of: "Other").location
        XCTAssertEqual((text.attribute(.wdDecoration, at: at, effectiveRange: nil) as? LinkDecoration)?.symbol, "bookmark")
        XCTAssertEqual((text.attribute(.wdDecoration, at: other, effectiveRange: nil) as? LinkDecoration)?.symbol, "globe")
        XCTAssertEqual(text.attribute(.toolTip, at: at, effectiveRange: nil) as? String, mark.tooltip(url: "https://grafana.example/d/latency"))
        XCTAssertEqual(text.attribute(.wdWebIcon, at: other, effectiveRange: nil) as? String, "https://other.example", "the icon is a button")
        XCTAssertNil(text.attribute(.wdWebIcon, at: bare.location, effectiveRange: nil), "bare URLs have no icon")
    }

    func testApplyingNeverChangesTheString() {
        let t = "# H\n- [ ] a **b** `c`\n[x](gly://item/\(id)) [[m]] https://example.com"
        let s = NSMutableAttributedString(string: t)
        MarkdownAttributes.apply(runs(t), to: s)
        XCTAssertEqual(s.string, t)
        XCTAssertNotNil(s.attribute(.wdLink, at: (t as NSString).range(of: "https").location, effectiveRange: nil))
        XCTAssertEqual(s.attribute(.wdHidden, at: (t as NSString).range(of: "](gly").location, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(s.attribute(.wdCheckbox, at: (t as NSString).range(of: "[ ]").location, effectiveRange: nil) as? Bool, false)
    }
}

extension MarkdownStylerTests {
    /// link-disambiguation K3: icon and qualifier are drawn into kerning space; the string never changes.
    func testDecorationAndKerningAroundChips() {
        let t = "see [Goals](gly://item/\(id)) now"
        let s = NSMutableAttributedString(string: t)
        MarkdownAttributes.apply(runs(t, appearance: .live(title: "Goals", kind: .page, qualifier: "person/alex")), to: s)
        XCTAssertEqual(s.string, t)
        let label = (t as NSString).range(of: "Goals")
        let deco = s.attribute(.wdDecoration, at: label.location, effectiveRange: nil) as? LinkDecoration
        XCTAssertEqual(deco?.symbol, "doc.text")
        XCTAssertEqual(deco?.qualifier, "person/alex")
        XCTAssertNotNil(s.attribute(.kern, at: label.location - 1, effectiveRange: nil), "room for the icon before the label")
        XCTAssertNotNil(s.attribute(.kern, at: NSMaxRange(label), effectiveRange: nil), "room for the qualifier after it")
    }

    func testTaskIconAndWebGlobe() {
        let t = "[Do it](gly://item/\(id)) [docs](https://example.com) https://example.com/x"
        let s = NSMutableAttributedString(string: t)
        MarkdownAttributes.apply(runs(t, appearance: .live(title: "Do it", kind: .task)), to: s)
        XCTAssertEqual((s.attribute(.wdDecoration, at: 1, effectiveRange: nil) as? LinkDecoration)?.symbol, "checkmark.circle")
        let docs = (t as NSString).range(of: "docs")
        XCTAssertEqual((s.attribute(.wdDecoration, at: docs.location, effectiveRange: nil) as? LinkDecoration)?.symbol, "globe")
        let bare = (t as NSString).range(of: "https://example.com/x")
        XCTAssertNil(s.attribute(.wdDecoration, at: bare.location, effectiveRange: nil), "bare URLs show the address itself")
    }
}
