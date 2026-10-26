import Foundation
import XCTest
import WorkDashCore
@testable import WorkDashEditor

final class MarkdownBlocksTests: XCTestCase {
    func testBlocks() {
        let text = "# Title\n\npara one\nstill para\n- item\n  - nested\n1. first\n- [ ] open\n- [x] done\n> quote\n```\ncode # here\n```"
        XCTAssertEqual(MarkdownBlocks.parse(text), [
            .heading(level: 1, text: "Title"), .blank, .paragraph("para one\nstill para"),
            .listItem(indent: 0, marker: "-", text: "item"), .listItem(indent: 1, marker: "-", text: "nested"),
            .listItem(indent: 0, marker: "1.", text: "first"),
            .checklistItem(indent: 0, checked: false, text: "open", line: 7), .checklistItem(indent: 0, checked: true, text: "done", line: 8),
            .quote("quote"), .code("code # here"),
        ])
    }

    func testToggleChecklist() {
        let text = "intro\n- [ ] send agenda\n  * [x] nested done\n- not a box"
        XCTAssertEqual(MarkdownBlocks.toggleChecklist(text, line: 1), "intro\n- [x] send agenda\n  * [x] nested done\n- not a box")
        XCTAssertEqual(MarkdownBlocks.toggleChecklist(text, line: 2), "intro\n- [ ] send agenda\n  * [ ] nested done\n- not a box")
        XCTAssertEqual(MarkdownBlocks.toggleChecklist(text, line: 3), text)
        XCTAssertEqual(MarkdownBlocks.toggleChecklist(text, line: 9), text)
    }

    func testInlineLinks() {
        let id = "0E5A3C1D-2B4F-4A6E-9C8D-1F2E3D4C5B6A"
        let a = MarkdownBlocks.inline("see [old label](workdash://item/\(id)), [[New page]] and [web](https://example.com)") { _ in .live(title: "Current title") }
        XCTAssertEqual(String(a.characters), "see Current title, New page and web", "live links show the current title, syntax is gone")
        let links = a.runs.compactMap { $0.link?.absoluteString }
        XCTAssertEqual(links, ["workdash://item/\(id)", "workdash://missing/New%20page", "https://example.com"])
    }

    func testDeletedTargetIsStruckThrough() {
        let id = "0E5A3C1D-2B4F-4A6E-9C8D-1F2E3D4C5B6A"
        let a = MarkdownBlocks.inline("[x](workdash://item/\(id))") { _ in .deleted(title: "x") }
        XCTAssertEqual(a.runs.first?.strikethroughStyle, .single)
    }

    // MARK: trash-bin 3.1 (link menu)

    func testPinADeletedTargetToASameTitledItem() {
        let old = "0F8B6C3E-2D4A-4E1B-9C7D-5A6B7C8D9E0F", new = "1A2B3C4D-5E6F-4A1B-8C2D-3E4F5A6B7C8D"
        let text = "see [Goals](workdash://item/\(old)) and again [Goals](workdash://item/\(old))"
        let pinned = MarkdownBlocks.pin(text, target: .item(old.lowercased()), with: "[Goals](workdash://item/\(new))")
        XCTAssertEqual(pinned, "see [Goals](workdash://item/\(new)) and again [Goals](workdash://item/\(old))", "first link only, ids case-insensitive")
        XCTAssertEqual(MarkdownBlocks.pin(text, target: .item(new), with: "x"), text, "no such link: unchanged")
    }

    func testTargetFromURL() {
        XCTAssertEqual(ParsedLink.Target(url: URL(string: "workdash://item/abc")!), .item("ABC"))
        XCTAssertEqual(ParsedLink.Target(url: URL(string: LinkParser.missingURL("person/alex/Goals"))!), .missing("person/alex/Goals"))
        XCTAssertNil(ParsedLink.Target(url: URL(string: "https://example.com")!))
    }

    func testMissingMenuModelAndReadOnlyFilter() {
        let candidate = LinkSuggestion(id: "1", symbol: "doc.text", title: "Goals · alex", subtitle: "", insert: "[Goals](workdash://item/1)")
        let model = LinkMenuModel.missing(typed: "person/alex/Call", candidates: [candidate])
        XCTAssertEqual(model.sections[0], [.replace(candidate)])
        XCTAssertEqual(model.sections[1].compactMap { if case .open(let title, _, _) = $0 { title } else { nil } },
                       ["New page “Call” in person/alex", "New task “Call” in person/alex"])
        XCTAssertEqual(model.withoutReplacements.sections[0], [])
        XCTAssertNil(LinkMenuModel.standard(.item("x")))
    }
}
