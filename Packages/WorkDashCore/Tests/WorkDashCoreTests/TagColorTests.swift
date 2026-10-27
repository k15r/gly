import GRDB
import XCTest
@testable import WorkDashCore

/// specs/tags "Tag colors", "Set a tag color in the tag list", tag management (tag-colors C1–C9).
final class TagColorTests: XCTestCase {
    let me = "user@mac-test01"
    var db: DatabaseQueue!
    var h: CommandHandler!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    @discardableResult
    func ok(_ c: Command) -> CommandOK {
        guard case .ok(let r) = h.perform(c, writer: me) else { XCTFail("\(c)"); return CommandOK() }
        return r
    }
    func failure(_ c: Command) -> CommandFailure? { if case .failure(let f) = h.perform(c, writer: me) { return f }; return nil }
    func colors() throws -> TagColors { try db.read { try TagQueries.colors($0) } }
    func setColor(_ name: String, _ color: String?) throws {
        try db.write { db in
            let key = TagName.key(for: name)
            if let id = try String.fetchOne(db, sql: "SELECT id FROM tags WHERE name_key = ?", arguments: [key]) {
                try db.execute(sql: "UPDATE tags SET color = ? WHERE id = ?", arguments: [color, id])
            } else {
                try Batch(db: db, writer: me).insert("tags", ["name": name, "name_key": key, "page_body": "", "color": color])
            }
        }
    }

    // MARK: 1.1

    func testColorAGroup() throws {
        try setColor("person", "green")
        let c = try colors()
        XCTAssertEqual(c.effective("person").color, .green)
        XCTAssertEqual(c.effective("person").source, .own)
        XCTAssertEqual(c.effective("person/alex/blargh").color, .green)
        XCTAssertEqual(c.effective("Person/Alex").source, .inherited(from: "person"))
    }

    func testOverrideBelow() throws {
        try setColor("person", "green")
        try setColor("person/alex", "orange")
        let c = try colors()
        XCTAssertEqual(c.color("person/alex"), .orange)
        XCTAssertEqual(c.effective("person/alex/blargh").source, .inherited(from: "person/alex"))
        XCTAssertEqual(c.color("person/sam"), .green)
    }

    func testNoColorsSetUsesTheEarlierAutomaticColors() throws {
        let c = TagColors()
        XCTAssertEqual(c.effective("project/atlas").source, .automatic)
        XCTAssertEqual(c.color("project/atlas"), c.color("project/beta"), "same for every project/… tag")
        // Same hues as the chips before colors could be chosen (hash over the root key into this cycle).
        let earlier: (String) -> TagColor = { root in
            let hash = root.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
            return [TagColor.blue, .purple, .teal, .orange, .pink, .green, .indigo, .brown][hash % 8]
        }
        for root in ["person", "project", "topic", "x"] { XCTAssertEqual(c.color(root + "/a"), earlier(root), root) }
    }

    func testUnknownStoredNameCountsAsNone() throws {
        try setColor("person", "chartreuse")
        XCTAssertEqual(try colors().effective("person").source, .automatic)
    }

    func testExistingTagsHaveNoOwnColor() throws {
        // tags.color exists since v1 and was never written: every existing tag is automatic.
        ok(.createTag(name: "person/alex"))
        XCTAssertEqual(try colors().own, [:])
    }

    // MARK: 1.2

    func testSetAndClearAColorWithUndo() throws {
        ok(.createTag(name: "person/alex"))
        ok(.updateTagPage(name: "person/alex", body: "Team lead"))
        ok(.setTagColor(name: "person", color: .green))           // group name without a row
        ok(.setTagColor(name: "person/alex", color: .orange))
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Color of tag “person/alex”")
        XCTAssertEqual(try colors().color("person/alex/blargh"), .orange)
        ok(.setTagColor(name: "person/alex", color: nil))          // back to automatic = inherit
        XCTAssertEqual(try colors().effective("person/alex").source, .inherited(from: "person"))
        try db.write { db in _ = try db.undo(writer: me) }
        XCTAssertEqual(try colors().color("person/alex"), .orange, "one undo brings orange back")
        XCTAssertEqual(try db.read { try String.fetchOne($0, sql: "SELECT page_body FROM tags WHERE name_key = 'person/alex'") }, "Team lead")
        XCTAssertEqual(try db.read { try String.fetchOne($0, sql: "SELECT name FROM live_tags WHERE name_key = 'person'") }, "person")
    }

    func testColorOfAGroupLabelAndUnchangedColor() throws {
        ok(.setTagColor(name: "project", color: .blue))
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Color of tag “project”")
        XCTAssertFalse(ok(.setTagColor(name: "project", color: .blue)).changed)
    }
}
