import XCTest
@testable import GlyCore

/// specs/item-browser "Item browser and preset views", "Saved views" (item-browser I3).
final class ItemViewTests: XCTestCase {
    func testPresets() {
        XCTAssertEqual(ItemView.presets.map(\.name), ["All items", "Tasks", "Pages", "Bookmarks", "Meetings"])
        XCTAssertEqual(ItemView.tasks.query.description, "is:task status:open status:snoozed")
        XCTAssertEqual(ItemView.tasks.sort, .taskOrder)
        XCTAssertTrue(ItemView.all.query.isEmpty)
        let tag = ItemView.tag("Project/Atlas")
        XCTAssertEqual(tag.id, "tag:project/atlas")
        XCTAssertEqual(tag.query.tags, ["Project/Atlas"])
        XCTAssertEqual(tag.grouping, .kind)
        XCTAssertTrue(tag.isTagView)
    }

    func testSavedViewsRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ItemViewTests-\(UUID().uuidString)"))
        XCTAssertEqual(SavedViews.load(defaults), [])
        let view = ItemView(id: "v1", name: "Atlas this week", symbol: "star", query: ItemQuery.parse("is:task #project/atlas due:week"),
                            grouping: .due, sort: .due)
        SavedViews.save([view], defaults)
        XCTAssertEqual(SavedViews.load(defaults), [view])
        // Stored as text: readable, and robust against later query fields.
        let json = String(data: try XCTUnwrap(defaults.data(forKey: SavedViews.defaultsKey)), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("is:task #project\\/atlas due:week") || json.contains("is:task #project/atlas due:week"), json)
        defaults.set(Data(##"[{"id":"v2","name":"Old","query":"#a","grouping":"weird"}]"##.utf8), forKey: SavedViews.defaultsKey)
        XCTAssertEqual(SavedViews.load(defaults).first?.grouping, ItemGrouping.none, "unknown values fall back")
        XCTAssertEqual(SavedViews.load(defaults).first?.sort, .changed)
    }
}
