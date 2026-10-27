import XCTest
@testable import GlyCore

final class TagNameTests: XCTestCase {
    func testHierarchicalTag() throws {
        let t = try TagName("person/alex")
        XCTAssertEqual(t.display, "person/alex")
        XCTAssertEqual(t.segments, ["person", "alex"])
    }

    func testTrimsWhitespaceAndSlashes() throws {
        XCTAssertEqual(try TagName("  /project/atlas/ ").display, "project/atlas")
        XCTAssertEqual(try TagName("project / atlas").display, "project/atlas")
    }

    func testRejectsEmptySegmentsAndEmptyNames() {
        XCTAssertThrowsError(try TagName("project//atlas")) { XCTAssertEqual($0 as? TagName.Invalid, .emptySegment("project//atlas")) }
        XCTAssertThrowsError(try TagName("  ")) { XCTAssertEqual($0 as? TagName.Invalid, .empty) }
        XCTAssertThrowsError(try TagName("///"))
        XCTAssertThrowsError(try TagName("a/ /b"))
    }

    func testCaseInsensitiveIdentityKeepsDisplayCasing() throws {
        let a = try TagName("Person/Alex"), b = try TagName("person/alex")
        XCTAssertEqual(a.key, b.key)
        XCTAssertEqual(a.display, "Person/Alex")
        XCTAssertEqual(try TagName("Übergabe").key, try TagName("übergabe").key, "non-ASCII folds too")
    }
}
