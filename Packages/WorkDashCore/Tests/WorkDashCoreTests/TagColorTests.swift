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

    // MARK: 1.3

    func tags(of id: String) throws -> [String] {
        try db.read { try String.fetchAll($0, sql: "SELECT t.name FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE it.item_id = ? ORDER BY t.name_key", arguments: [id]) }
    }
    func liveTagNames() throws -> [String] { try db.read { try String.fetchAll($0, sql: "SELECT name FROM live_tags ORDER BY name_key") } }
    func body(_ id: String) throws -> String { try db.read { try String.fetchOne($0, sql: "SELECT body FROM items WHERE id = ?", arguments: [id])! } }
    func undo() throws { try db.write { db in _ = try db.undo(writer: me) } }

    func testRenameAGroup() throws {
        let a = ok(.createTask(TaskDraft(title: "A", tags: ["person/alex"]))).id!
        let b = ok(.createTask(TaskDraft(title: "B", tags: ["person/sam"]))).id!
        let alexTag = try db.read { try String.fetchOne($0, sql: "SELECT id FROM tags WHERE name_key = 'person/alex'")! }
        let page = ok(.createPage(PageDraft(title: "Hub", body: "see [person/alex](workdash://tag/\(alexTag))"))).id!
        ok(.renameTag(from: "person", to: "people"))
        XCTAssertEqual(try liveTagNames(), ["people/alex", "people/sam"])
        XCTAssertEqual(try tags(of: a), ["people/alex"])
        XCTAssertEqual(try tags(of: b), ["people/sam"])
        XCTAssertEqual(try body(page), "see [people/alex](workdash://tag/\(alexTag))", "link label follows")
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Rename tag “person” to “people”")
    }

    func testFixATypoWithOneUndo() throws {
        let a = ok(.createTask(TaskDraft(title: "A", tags: ["projct/atlas"]))).id!
        ok(.renameTag(from: "projct/atlas", to: "project/atlas"))
        XCTAssertEqual(try tags(of: a), ["project/atlas"])
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Rename tag “projct/atlas” to “project/atlas”")
        try undo()
        XCTAssertEqual(try tags(of: a), ["projct/atlas"])
    }

    func testMergeTwoSpellings() throws {
        let t1 = ok(.createTask(TaskDraft(title: "T1", tags: ["person/al"]))).id!
        let both = ok(.createTask(TaskDraft(title: "Both", tags: ["person/al", "person/alex"]))).id!
        let page = ok(.createPage(PageDraft(title: "P", tags: ["person/alex"]))).id!
        ok(.updateTagPage(name: "person/al", body: "old notes"))
        ok(.updateTagPage(name: "person/alex", body: "Team lead"))
        ok(.setTagColor(name: "person/al", color: .pink))
        let alTag = try db.read { try String.fetchOne($0, sql: "SELECT id FROM tags WHERE name_key = 'person/al'")! }
        let alexTag = try db.read { try String.fetchOne($0, sql: "SELECT id FROM tags WHERE name_key = 'person/alex'")! }
        let hub = ok(.createPage(PageDraft(title: "Hub", body: "[person/al](workdash://tag/\(alTag))"))).id!

        XCTAssertEqual(failure(.renameTag(from: "person/al", to: "person/alex"))?.code, .conflict, "asks first")
        XCTAssertEqual(try tags(of: t1), ["person/al"], "nothing changed without merge")

        ok(.renameTag(from: "person/al", to: "person/alex", merge: true))
        XCTAssertEqual(try tags(of: t1), ["person/alex"])
        XCTAssertEqual(try tags(of: both), ["person/alex"], "no duplicate assignment")
        XCTAssertEqual(try tags(of: page), ["person/alex"])
        XCTAssertEqual(try liveTagNames(), ["person/alex"])
        XCTAssertEqual(try db.read { try String.fetchOne($0, sql: "SELECT page_body FROM tags WHERE id = ?", arguments: [alexTag]) }, "Team lead\n\nold notes")
        XCTAssertEqual(try colors().color("person/alex"), .pink, "target had no own color")
        XCTAssertEqual(try body(hub), "[person/alex](workdash://tag/\(alexTag))", "link rewritten to the merged tag")
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Merge tag “person/al”")

        try undo()
        XCTAssertEqual(try tags(of: t1), ["person/al"])
        XCTAssertEqual(try tags(of: both), ["person/al", "person/alex"])
        XCTAssertEqual(try body(hub), "[person/al](workdash://tag/\(alTag))")
        XCTAssertEqual(try liveTagNames(), ["person/al", "person/alex"])
    }

    func testPartialSubtreeClash() throws {
        let a = ok(.createTask(TaskDraft(title: "A", tags: ["person/alex"]))).id!
        let s1 = ok(.createTask(TaskDraft(title: "S1", tags: ["person/sam"]))).id!
        let s2 = ok(.createTask(TaskDraft(title: "S2", tags: ["people/sam"]))).id!
        let f = failure(.renameTag(from: "person", to: "people"))
        XCTAssertEqual(f?.code, .conflict)
        XCTAssertTrue(f?.message.contains("people/sam") ?? false, f?.message ?? "")
        ok(.renameTag(from: "person", to: "people", merge: true))
        XCTAssertEqual(try tags(of: a), ["people/alex"])
        XCTAssertEqual(try tags(of: s1), ["people/sam"])
        XCTAssertEqual(try tags(of: s2), ["people/sam"])
        XCTAssertEqual(try liveTagNames(), ["people/alex", "people/sam"])
    }

    func testRenameIntoItselfIsRejected() {
        ok(.createTag(name: "a"))
        XCTAssertEqual(failure(.renameTag(from: "a", to: "a/b"))?.code, .validation)
        XCTAssertEqual(failure(.renameTag(from: "nope", to: "x"))?.code, .notFound)
    }

    func testDeleteAUsedTagWithOneUndo() throws {
        let ids = (1...3).map { ok(.createTask(TaskDraft(title: "T\($0)", tags: ["project/old", "keep"]))).id! }
        ok(.createTag(name: "project/old/sub"))
        XCTAssertEqual(try db.read { try TagQueries.usage($0, name: "Project/Old") }, 3)
        ok(.deleteTag(name: "project/old"))
        for id in ids { XCTAssertEqual(try tags(of: id), ["keep"]) }
        XCTAssertEqual(try liveTagNames(), ["keep", "project/old/sub"], "subtags stay")
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: me) }, "Delete tag “project/old”")
        try undo()
        for id in ids { XCTAssertEqual(try tags(of: id), ["keep", "project/old"]) }
        XCTAssertEqual(failure(.deleteTag(name: "project"))?.code, .notFound, "group name without a row")
    }

    func testTagOfFinishedWork() throws {
        let t = ok(.createTask(TaskDraft(title: "Done", tags: ["person/old"]))).id!
        ok(.setStatus(id: t, .done))
        ok(.createTask(TaskDraft(title: "Open", tags: ["person/alex"])))
        let hidden = try db.read { try TagQueries.tagTree($0, today: "2026-10-27") }
        XCTAssertEqual(hidden.first?.children.map(\.segment), ["alex"])
        let shown = try db.read { try TagQueries.tagTree($0, today: "2026-10-27", includeUnused: true) }
        let old = shown.first?.children.first { $0.segment == "old" }
        XCTAssertEqual(old?.unused, true)
        XCTAssertEqual(shown.first?.children.first { $0.segment == "alex" }?.unused, false)
    }
}
