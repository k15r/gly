import AppKit
import XCTest
import GlyCore
@testable import GlyEditor

/// live-preview L1: specs/markdown-editing "Live preview".
final class LivePreviewTests: XCTestCase {
    let id = "0E5A3C1D-2B4F-4A6E-9C8D-1F2E3D4C5B6A"

    /// Styles at `substring` after the live-preview pass, with the caret at `caret` (nil = no line revealed).
    func styles(_ text: String, at substring: String, caret: Int? = nil, occurrence: Int = 0) -> [StyleRun.Style] {
        let ns = text as NSString
        var r = ns.range(of: substring)
        for _ in 0..<occurrence { r = ns.range(of: substring, range: NSRange(location: NSMaxRange(r), length: ns.length - NSMaxRange(r))) }
        let base = MarkdownStyler.runs(for: text) { _ in .live(title: "T") }
        let revealed = caret.map { [NSRange(location: $0, length: 0)] } ?? []
        return MarkdownStyler.livePreview(base, text: text, revealed: revealed).filter { $0.range == r }.map(\.style)
    }

    func testHeadingHiddenOffTheCaretLine() {
        // "Heading while typing" / "Back on the line".
        let t = "## Decisions\nnext"
        XCTAssertEqual(styles(t, at: "## ", caret: 15), [.hidden])
        XCTAssertEqual(styles(t, at: "## ", caret: 3), [.syntax], "caret on the heading shows the raw syntax")
    }

    func testEmphasisAndCodeMarkers() {
        let t = "a **bold** and *it* and `code`\nother"
        XCTAssertEqual(styles(t, at: "**", caret: 33), [.hidden])
        XCTAssertEqual(styles(t, at: "*", caret: 33, occurrence: 4), [.hidden], "italic marker")
        XCTAssertEqual(styles(t, at: "`", caret: 33), [.hidden])
        XCTAssertEqual(styles(t, at: "**", caret: 0), [.syntax])
    }

    func testListsQuotesAndCheckboxes() {
        let t = "- item\n1. first\n> quoted\n- [ ] todo\n- [x] done\nlast"
        let caret = (t as NSString).length
        XCTAssertEqual(styles(t, at: "-", caret: caret), [.bullet])
        XCTAssertEqual(styles(t, at: "1.", caret: caret), [], "numbers stay as written")
        XCTAssertEqual(styles(t, at: "> ", caret: caret), [.quoteBar])
        XCTAssertEqual(styles(t, at: "- ", caret: caret, occurrence: 1), [.invisible], "checkbox line marker")
        XCTAssertEqual(styles(t, at: "[ ]", caret: caret), [.checkbox(checked: false), .checkboxGlyph(checked: false)])
        XCTAssertEqual(styles(t, at: "[x]", caret: caret), [.checkbox(checked: true), .checkboxGlyph(checked: true)])
        // On the caret line the raw checkbox stays clickable text.
        let onTodo = (t as NSString).range(of: "todo").location
        XCTAssertEqual(styles(t, at: "[ ]", caret: onTodo), [.checkbox(checked: false)])
    }

    func testFenceLinesHidden() {
        let t = "```\ncode\n```\nafter"
        XCTAssertEqual(styles(t, at: "```", caret: 15), [.codeBlock, .hidden], "the fence line keeps its block background")
        XCTAssertEqual(styles(t, at: "```", caret: 1), [.codeBlock, .syntax])
    }

    func testCaretInsideACodeBlockShowsBothFences() {
        // "Inside a code block": the caret on a code line shows the opening and closing fence.
        let t = "intro\n```\ncode\n```\nafter"
        let onCode = (t as NSString).range(of: "code").location
        XCTAssertEqual(styles(t, at: "```", caret: onCode), [.codeBlock, .syntax])
        XCTAssertEqual(styles(t, at: "```", caret: onCode, occurrence: 1), [.codeBlock, .syntax])
        XCTAssertEqual(styles(t, at: "```", caret: 0, occurrence: 1), [.codeBlock, .hidden], "caret outside the block")
    }

    func testLinkSyntaxRevealedOnTheCaretLine() {
        // "Link chip": collapsed off the line, visible while editing it.
        let t = "see [Plan](gly://item/\(id)) here\nnext"
        let hidden = styles(t, at: "](gly://item/\(id))", caret: (t as NSString).length)
        XCTAssertEqual(hidden, [.hidden])
        XCTAssertEqual(styles(t, at: "](gly://item/\(id))", caret: 0), [.syntax])
    }

    func testSelectionAcrossLinesRevealsAll() {
        let t = "# One\n# Two\n# Three"
        let base = MarkdownStyler.runs(for: t) { _ in .live(title: "T") }
        let out = MarkdownStyler.livePreview(base, text: t, revealed: [NSRange(location: 2, length: 6)])
        let markers = out.filter { (t as NSString).substring(with: $0.range) == "# " }.map(\.style)
        XCTAssertEqual(markers, [.syntax, .syntax, .hidden])
    }

    func testCaretAtTheVeryEndRevealsTheLastLine() {
        let t = "intro\n## Title"
        XCTAssertEqual(styles(t, at: "## ", caret: (t as NSString).length), [.syntax])
    }

    func testStoredTextIsUntouched() {
        let t = "## H\n- [ ] a **b**"
        let storage = NSTextStorage(string: t)
        let base = MarkdownStyler.runs(for: t) { _ in .live(title: "T") }
        MarkdownAttributes.apply(MarkdownStyler.livePreview(base, text: t, revealed: []), to: storage)
        XCTAssertEqual(storage.string, t)
    }
}
