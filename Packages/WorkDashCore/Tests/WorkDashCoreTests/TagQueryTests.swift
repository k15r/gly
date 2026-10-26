import GRDB
import XCTest
@testable import WorkDashCore

final class TagQueryTests: XCTestCase {
    var db: DatabaseQueue!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory() }

    func titles(_ db: Database, filter: String) throws -> Set<String> {
        let f = TagFilter(try TagName(filter))
        return Set(try String.fetchAll(db, sql: "SELECT i.title FROM live_items i WHERE \(f.sql)", arguments: f.arguments))
    }

    func testFilterIncludesDescendants() throws {
        try db.write { db in
            try addTask(db, "A", tags: ["project/atlas"])
            try addTask(db, "B", tags: ["project/atlas/logs"])
            try addTask(db, "C", tags: ["projects-old"])
            XCTAssertEqual(try titles(db, filter: "project"), ["A", "B"])
            XCTAssertEqual(try titles(db, filter: "Project/Atlas"), ["A", "B"], "case-insensitive")
            XCTAssertEqual(try titles(db, filter: "project/atlas/logs"), ["B"])
        }
    }

    func testNoPartialSegmentMatch() throws {
        try db.write { db in
            try addTask(db, "A", tags: ["person/alex"])
            XCTAssertEqual(try titles(db, filter: "person/al"), [])
        }
    }

    func testLikeWildcardsInTagNamesAreEscaped() throws {
        try db.write { db in
            try addTask(db, "A", tags: ["a_b/x"])
            try addTask(db, "B", tags: ["axb/x"])
            XCTAssertEqual(try titles(db, filter: "a_b"), ["A"])
        }
    }

    func testFilterIgnoresRemovedAssignments() throws {
        try db.write { db in
            let id = try addTask(db, "A", tags: ["person/alex"])
            let assignment = try String.fetchOne(db, sql: "SELECT id FROM item_tags WHERE item_id = ?", arguments: [id])!
            try Batch(db: db, writer: "u").softDelete("item_tags", id: assignment)
            XCTAssertEqual(try titles(db, filter: "person"), [])
        }
    }

    func testTagTreeWithRollUpCounts() throws {
        try db.write { db in
            try addTask(db, "A", tags: ["person/alex"])
            try addTask(db, "B", tags: ["person/alex", "person/sam"])   // counted once under `person`
            try addTask(db, "C", tags: ["person/sam"])
            try addTask(db, "Done", tags: ["person/alex"], status: "done")
            try addTask(db, "Later", tags: ["project/atlas"], status: "snoozed", snoozedUntil: "2026-11-01")
            try addTask(db, "Back", tags: ["project/atlas"], status: "snoozed", snoozedUntil: "2026-10-27")
            let tree = try TagQueries.tagTree(db, today: "2026-10-27")
            XCTAssertEqual(tree.map(\.path), ["person", "project"])
            let person = tree[0]
            XCTAssertFalse(person.isTag, "group node")
            XCTAssertEqual(person.openCount, 3)
            XCTAssertEqual(person.children.map { "\($0.segment)=\($0.openCount)" }, ["alex=2", "sam=2"])
            XCTAssertTrue(person.children.allSatisfy(\.isTag))
            XCTAssertEqual(tree[1].openCount, 2, "snoozed tasks count as open, like in the task list")
        }
    }

    func testEmptyTagShowsButDoneOnlyTagHides() throws {
        try db.write { db in
            try addTask(db, "A", tags: ["person/alex"])
            try addTask(db, "Done", tags: ["person/old"], status: "done")
        }
        let h = CommandHandler(writer: db)
        _ = h.perform(.createTag(name: "person/alex/goals"), writer: "me")
        let tree = try db.read { try TagQueries.tagTree($0, today: "2026-10-27") }
        let alex = tree[0].children.first { $0.segment == "alex" }
        XCTAssertEqual(tree[0].children.map(\.segment), ["alex"], "person/old has only a done task")
        XCTAssertEqual(alex?.children.map { "\($0.segment)=\($0.openCount)" }, ["goals=0"])
        XCTAssertEqual(alex?.children.first?.isTag, true)
        XCTAssertEqual(tree[0].openCount, 1)
    }

    func testTagTreeMatchesSpecScenario() throws {
        // specs/tags: two open tasks tagged person/alex and one person/sam -> person (3), alex (2), sam (1)
        try db.write { db in
            try addTask(db, "1", tags: ["person/alex"])
            try addTask(db, "2", tags: ["person/alex"])
            try addTask(db, "3", tags: ["person/sam"])
            let tree = try TagQueries.tagTree(db, today: "2026-10-27")
            XCTAssertEqual(tree.first?.openCount, 3)
            XCTAssertEqual(tree.first?.children.map { "\($0.segment)=\($0.openCount)" }, ["alex=2", "sam=1"])
        }
    }
}
