import GRDB
import XCTest
@testable import GlyCore

/// specs/app-identity "Take over data from WorkDash", design R2.
final class LegacyMigrationTests: XCTestCase {
    var dir: URL!
    var legacy: URL { dir.appendingPathComponent("legacy/workdash.sqlite") }
    var fresh: URL { dir.appendingPathComponent("new/gly.sqlite") }
    var oldDefaults: UserDefaults!
    var newDefaults: UserDefaults!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for sub in ["legacy", "new"] { try FileManager.default.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true) }
        oldDefaults = UserDefaults(suiteName: "test.legacy.\(UUID().uuidString)")
        newDefaults = UserDefaults(suiteName: "test.new.\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// A WorkDash-era store: a task, a page linking it with the old scheme, a tag page linking the tag.
    func makeLegacyStore() throws -> (task: String, page: String) {
        let pool = try StoreFactory.openReadWrite(at: legacy)
        let h = CommandHandler(writer: pool)
        guard case .ok(let t) = h.perform(.createTask(TaskDraft(title: "Call venue", tags: ["project/atlas"])), writer: "user@mac-1"),
              case .ok(let p) = h.perform(.createPage(PageDraft(title: "Plan", body: "x")), writer: "user@mac-1") else { XCTFail(); throw CancellationError() }
        try pool.write { db in
            try db.execute(sql: "UPDATE items SET body = ? WHERE id = ?", arguments: ["see [Call venue](workdash://item/\(t.id!))", p.id!])
            let tag = try String.fetchOne(db, sql: "SELECT id FROM tags WHERE name_key = 'project/atlas'")!
            try db.execute(sql: "UPDATE tags SET page_body = ? WHERE id = ?", arguments: ["[atlas](workdash://tag/\(tag))", tag])
        }
        try pool.close()
        oldDefaults.set(600, forKey: "workingStartMinute")
        oldDefaults.set("tok", forKey: "httpToken")
        oldDefaults.set("mac-1", forKey: "deviceID")
        return (t.id!, p.id!)
    }

    func takeOver() throws -> LegacyMigration.Result {
        try LegacyMigration.run(newDatabase: fresh, legacyDatabase: legacy, newDefaults: newDefaults, legacyDefaults: oldDefaults)
    }

    func testFirstStartWithGlyData() throws {
        let (task, page) = try makeLegacyStore()
        let r = try takeOver()
        XCTAssertTrue(r.copied)
        XCTAssertEqual(r.items, 2)
        XCTAssertEqual(r.tags, 1)
        XCTAssertEqual(r.rewrittenTexts, 2)
        XCTAssertEqual(r.settingsCopied, 3)
        let db = try StoreFactory.openReadWrite(at: fresh)
        XCTAssertEqual(try db.read { try String.fetchOne($0, sql: "SELECT body FROM items WHERE id = ?", arguments: [page]) },
                       "see [Call venue](gly://item/\(task))")
        XCTAssertEqual(try db.read { try LinkQueries.backlinks($0, to: task) }.map(\.source.id), [page], "links keep their targets")
        XCTAssertEqual(try db.read { try $0.undoLabel(writer: "user@mac-1") }, "Create page “Plan”", "history came along")
        XCTAssertEqual(newDefaults.integer(forKey: "workingStartMinute"), 600)
        XCTAssertEqual(newDefaults.string(forKey: "httpToken"), "tok")
        XCTAssertEqual(newDefaults.string(forKey: "deviceID"), "mac-1")
        // The WorkDash store is unchanged.
        let old = try DatabaseQueue(path: legacy.path)
        XCTAssertEqual(try old.read { try String.fetchOne($0, sql: "SELECT body FROM items WHERE id = ?", arguments: [page]) },
                       "see [Call venue](workdash://item/\(task))")
    }

    func testLaterStartsCopyNothing() throws {
        _ = try makeLegacyStore()
        _ = try takeOver()
        let db = try StoreFactory.openReadWrite(at: fresh)
        _ = CommandHandler(writer: db).perform(.createTask(TaskDraft(title: "Made in gly")), writer: "user@mac-1")
        try db.close()
        newDefaults.set(480, forKey: "workingStartMinute")
        let again = try takeOver()
        XCTAssertFalse(again.copied)
        let reopened = try StoreFactory.openReadWrite(at: fresh)
        XCTAssertEqual(try reopened.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM live_items") }, 3, "gly's own change stays")
        XCTAssertEqual(newDefaults.integer(forKey: "workingStartMinute"), 480)
    }

    func testNoGlyStore() throws {
        let r = try takeOver()
        XCTAssertFalse(r.copied)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path), "nothing created; the agent opens a fresh store as usual")
    }
}
