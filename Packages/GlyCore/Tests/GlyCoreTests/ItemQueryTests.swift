import XCTest
@testable import GlyCore

/// specs/item-browser "Filter bar" (item-browser I1): tokens, text and the canonical form.
final class ItemQueryTests: XCTestCase {
    func testTypedTokens() {
        let q = ItemQuery.parse("is:task #project/atlas due:week review")
        XCTAssertEqual(q.kinds, [.task])
        XCTAssertEqual(q.tags, ["project/atlas"])
        XCTAssertEqual(q.due, .week)
        XCTAssertEqual(q.text, "review")
        XCTAssertEqual(q.tokens.count, 3, "three chips plus the text")
    }

    func testEveryToken() {
        let q = ItemQuery.parse("is:page is:bookmark -#ops untagged status:open,snoozed prio:high effort:xl changed:7d by:agent host:Example.com due:overdue")
        XCTAssertEqual(q.kinds, [.page, .bookmark])
        XCTAssertEqual(q.excludedTags, ["ops"])
        XCTAssertTrue(q.untagged)
        XCTAssertEqual(q.statuses, [.open, .snoozed])
        XCTAssertEqual(q.priorities, [.high])
        XCTAssertEqual(q.efforts, [.xl])
        XCTAssertEqual(q.changed, .days7)
        XCTAssertEqual(q.author, .agent)
        XCTAssertEqual(q.hosts, ["example.com"])
        XCTAssertEqual(q.due, .overdue)
        XCTAssertEqual(q.text, "")
        for (input, check) in [("due:today", ItemQuery.parse("due:today").due == .today), ("due:none", ItemQuery.parse("due:none").due == ItemQuery.Due.none),
                               ("changed:today", ItemQuery.parse("changed:today").changed == .today), ("changed:30d", ItemQuery.parse("changed:30d").changed == .days30),
                               ("by:me", ItemQuery.parse("by:me").author == .me), ("priority:urgent", ItemQuery.parse("priority:urgent").priorities == [.urgent]),
                               ("is:meeting", ItemQuery.parse("is:meeting").kinds == [.meeting]), ("status:dropped", ItemQuery.parse("status:dropped").statuses == [.dropped])] {
            XCTAssertTrue(check, input)
        }
    }

    func testUnknownTokensAreText() {
        let q = ItemQuery.parse("is:nothing due:later foo:bar # #bad//tag status:open,weird plain")
        XCTAssertTrue(q.kinds.isEmpty && q.due == nil && q.tags.isEmpty && q.statuses.isEmpty)
        XCTAssertEqual(q.text, "is:nothing due:later foo:bar # #bad//tag status:open,weird plain")
    }

    func testSingleValuedFiltersReplace() {
        XCTAssertEqual(ItemQuery.parse("due:today due:week").due, .week)
        XCTAssertEqual(ItemQuery.parse("#ops -#ops").tags, [], "a tag can't be wanted and excluded")
        XCTAssertEqual(ItemQuery.parse("#Ops #ops").tags, ["Ops"], "tags are identified case-insensitively")
    }

    func testRoundTrip() {
        for input in ["", "is:task #project/atlas due:week review", "is:page -#ops untagged prio:high effort:XL changed:30d by:me host:example.com",
                      "status:open status:snoozed is:task", "release notes"] {
            let q = ItemQuery.parse(input)
            XCTAssertEqual(ItemQuery.parse(q.description), q, input)
        }
        XCTAssertEqual(ItemQuery.parse("review is:task #a status:snoozed status:open").description, "is:task #a status:open status:snoozed review")
    }

    func testAddRemoveAndDroppingTags() {
        var q = ItemQuery.parse("is:task #a -#b untagged")
        q.remove(.tag("A"))
        XCTAssertEqual(q.tags, [])
        q.add(.excludedTag("c"))
        XCTAssertEqual(q.excludedTags, ["b", "c"])
        q.add(.tag("b"))
        XCTAssertEqual(q.tags, ["b"]); XCTAssertEqual(q.excludedTags, ["c"])
        XCTAssertEqual(q.droppingTags(), ItemQuery.parse("is:task"))
        XCTAssertTrue(ItemQuery.parse("").isEmpty)
    }
}
