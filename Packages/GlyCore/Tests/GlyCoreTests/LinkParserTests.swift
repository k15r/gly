import Foundation
import XCTest
@testable import GlyCore

final class LinkParserTests: XCTestCase {
    let page = "0E5A3C1D-2B4F-4A6E-9C8D-1F2E3D4C5B6A"
    let tag = "A1B2C3D4-E5F6-4711-8899-AABBCCDDEEFF"

    func testCanonicalItemAndTagLinks() {
        let text = "See [Atlas architecture](gly://item/\(page)) and [person/alex](gly://tag/\(tag.lowercased()))."
        let links = LinkParser.links(in: text)
        XCTAssertEqual(links.map(\.target), [.item(page), .tag(tag)], "ids are normalized to upper case")
        XCTAssertEqual(links.map(\.label), ["Atlas architecture", "person/alex"])
        XCTAssertEqual((text as NSString).substring(with: links[0].range), "[Atlas architecture](gly://item/\(page))")
    }

    func testMissingLinks() {
        let links = LinkParser.links(in: "Notes in [[Retro notes]] and [[ Spaced ]] but not [[]] or [single].")
        XCTAssertEqual(links.map(\.target), [.missing("Retro notes"), .missing("Spaced")])
    }

    func testBracketsInsideLabel() {
        let text = "[Plan [draft]](gly://item/\(page))"
        XCTAssertEqual(LinkParser.links(in: text).first?.label, "Plan [draft]")
    }

    func testCodeIsExcluded() {
        let text = """
            `[[Not a link]]` and [[Real]]
            ```
            [[Inside fence]] [x](gly://item/\(page))
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
        let text = "See [Atlas architecture](gly://item/\(page)) and [[Retro notes]]"
        XCTAssertEqual(LinkParser.plainText(text), "See Atlas architecture and Retro notes")
        XCTAssertEqual(LinkParser.plainText("[Design doc](https://example.com/doc) here"), "Design doc here")
    }

    func testCanonicalForm() {
        XCTAssertEqual(LinkParser.canonical(label: "A [b]", item: page), "[A (b)](gly://item/\(page))")
        XCTAssertEqual(LinkParser.links(in: LinkParser.canonical(label: "x", tag: tag)).first?.target, .tag(tag))
    }

    func testMissingURLKeepsTagPathWhole() throws {
        let url = try XCTUnwrap(URL(string: LinkParser.missingURL("person/alex/blargh/Dings & more")))
        XCTAssertEqual(LinkParser.missingText(url), "person/alex/blargh/Dings & more")
        XCTAssertNil(LinkParser.missingText(URL(string: "gly://item/x")!))
        XCTAssertEqual(LinkParser.missingCreateKind(url), .page)
        let task = try XCTUnwrap(URL(string: LinkParser.missingURL("a/b", create: .task)))
        XCTAssertEqual(LinkParser.missingText(task), "a/b")
        XCTAssertEqual(LinkParser.missingCreateKind(task), .task)
    }

    // MARK: rename-to-gly 1.1 (specs/app-identity "Links keep working")

    func testLegacySchemeIsReadLikeTheNewOne() throws {
        let id = "0F8B6C3E-2D4A-4E1B-9C7D-5A6B7C8D9E0F"
        let old = LinkParser.links(in: "see [Plan](workdash://item/\(id)) and [atlas](workdash://tag/\(id))")
        XCTAssertEqual(old.map(\.target), [.item(id), .tag(id)], "Pasted old link")
        XCTAssertEqual(old.first?.label, "Plan")
        XCTAssertTrue(LinkParser.isOwn(URL(string: "workdash://item/\(id)")!))
        XCTAssertTrue(LinkParser.isOwn(URL(string: "gly://item/\(id)")!))
        XCTAssertFalse(LinkParser.isOwn(URL(string: "https://example.com")!))
        XCTAssertEqual(LinkParser.missingText(URL(string: "workdash://missing/a%2Fb")!), "a/b")
    }

    func testNewLinksAreWrittenWithTheGlyScheme() {
        XCTAssertEqual(LinkParser.canonical(label: "Plan", item: "X"), "[Plan](gly://item/X)")
        XCTAssertTrue(LinkParser.missingURL("a/b").hasPrefix("gly://missing/"))
    }
}
