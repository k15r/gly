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
            .checklistItem(indent: 0, checked: false, text: "open"), .checklistItem(indent: 0, checked: true, text: "done"),
            .quote("quote"), .code("code # here"),
        ])
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
}
