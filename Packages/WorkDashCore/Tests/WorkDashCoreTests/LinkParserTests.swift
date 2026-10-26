import Foundation
import XCTest
@testable import WorkDashCore

final class LinkParserTests: XCTestCase {
    let page = "0E5A3C1D-2B4F-4A6E-9C8D-1F2E3D4C5B6A"
    let tag = "A1B2C3D4-E5F6-4711-8899-AABBCCDDEEFF"

    func testCanonicalItemAndTagLinks() {
        let text = "See [Atlas architecture](workdash://item/\(page)) and [person/alex](workdash://tag/\(tag.lowercased()))."
        let links = LinkParser.links(in: text)
        XCTAssertEqual(links.map(\.target), [.item(page), .tag(tag)], "ids are normalized to upper case")
        XCTAssertEqual(links.map(\.label), ["Atlas architecture", "person/alex"])
        XCTAssertEqual((text as NSString).substring(with: links[0].range), "[Atlas architecture](workdash://item/\(page))")
    }

    func testMissingLinks() {
        let links = LinkParser.links(in: "Notes in [[Retro notes]] and [[ Spaced ]] but not [[]] or [single].")
        XCTAssertEqual(links.map(\.target), [.missing("Retro notes"), .missing("Spaced")])
    }

    func testBracketsInsideLabel() {
        let text = "[Plan [draft]](workdash://item/\(page))"
        XCTAssertEqual(LinkParser.links(in: text).first?.label, "Plan [draft]")
    }

    func testCodeIsExcluded() {
        let text = """
            `[[Not a link]]` and [[Real]]
            ```
            [[Inside fence]] [x](workdash://item/\(page))
            ```
            after
            """
        XCTAssertEqual(LinkParser.links(in: text).map(\.target), [.missing("Real")])
    }

    func testUnclosedFenceRunsToTheEnd() {
        XCTAssertEqual(LinkParser.links(in: "```\n[[Nope]]").count, 0)
    }

    func testWebLinksAreIgnored() {
        XCTAssertEqual(LinkParser.links(in: "[Design doc](https://example.com/doc) https://example.com/x [mail](mailto:a@example.com)"), [])
    }

    func testRangesAreUTF16() {
        let text = "Über 🙂 [[Ziel]]"
        let link = LinkParser.links(in: text)[0]
        XCTAssertEqual((text as NSString).substring(with: link.range), "[[Ziel]]")
    }

    func testPlainTextForSearch() {
        let text = "See [Atlas architecture](workdash://item/\(page)) and [[Retro notes]]"
        XCTAssertEqual(LinkParser.plainText(text), "See Atlas architecture and Retro notes")
    }

    func testCanonicalForm() {
        XCTAssertEqual(LinkParser.canonical(label: "A [b]", item: page), "[A (b)](workdash://item/\(page))")
        XCTAssertEqual(LinkParser.links(in: LinkParser.canonical(label: "x", tag: tag)).first?.target, .tag(tag))
    }
}
