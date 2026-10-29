import GRDB
import XCTest
@testable import GlyCore

/// Saved views in the store (item-browser I3).
final class ViewStoreTests: XCTestCase {
    let me = "user@mac"
    var db: DatabaseQueue!
    var h: CommandHandler!
    override func setUpWithError() throws { db = try StoreFactory.openInMemory(); h = CommandHandler(writer: db) }

    @discardableResult
    func ok(_ c: Command, file: StaticString = #filePath, line: UInt = #line) -> CommandOK {
        switch h.perform(c, writer: me) {
        case .ok(let r): return r
        case .failure(let f): XCTFail("\(f)", file: file, line: line); return CommandOK()
        }
    }
    func failure(_ c: Command) -> CommandFailure? { if case .failure(let f) = h.perform(c, writer: me) { return f }; return nil }
    func views() throws -> [ItemView] { try db.read { try ViewQueries.list($0) } }
    func undoLabel() throws -> String? { try db.read { try $0.undoLabel(writer: me) } }

    func testCreateUpdateDeleteWithUndo() throws {
        let id = ok(.createView(ViewDraft(name: " Atlas this week ", query: "due:week #project/atlas is:task", grouping: .due, sort: .due))).id!
        XCTAssertEqual(try views().map(\.name), ["Atlas this week"])
        XCTAssertEqual(try views().first?.query.description, "is:task #project/atlas due:week", "stored in canonical form")
        XCTAssertEqual(try views().first?.grouping, .due)
        XCTAssertEqual(try undoLabel(), "Save view “Atlas this week”")

        ok(.updateView(id: id, ViewPatch(name: "Atlas", query: "is:task #project/atlas")))
        XCTAssertEqual(try views().first?.name, "Atlas")
        XCTAssertEqual(try undoLabel(), "Edit view “Atlas”")
        XCTAssertFalse(ok(.updateView(id: id, ViewPatch(name: "Atlas"))).changed)

        ok(.deleteView(id: id))
        XCTAssertEqual(try views(), [])
        XCTAssertEqual(try undoLabel(), "Delete view “Atlas”")
        ok(.undo)
        XCTAssertEqual(try views().map(\.name), ["Atlas"])
        ok(.undo); ok(.undo)
        XCTAssertEqual(try views(), [], "undoing the save removes it")
    }

    func testOrderAndValidation() throws {
        ok(.createView(ViewDraft(name: "B", query: "")))
        ok(.createView(ViewDraft(name: "A", query: "")))
        XCTAssertEqual(try views().map(\.name), ["B", "A"], "in the order they were saved")
        XCTAssertEqual(failure(.createView(ViewDraft(name: "  ", query: "")))?.code, .validation)
        XCTAssertEqual(failure(.updateView(id: "tasks", ViewPatch(name: "x")))?.code, .validation, "presets can't be changed")
        XCTAssertEqual(failure(.deleteView(id: "all"))?.code, .validation)
        XCTAssertEqual(failure(.deleteView(id: "nope"))?.code, .notFound)
    }

    func testV10MigrationAddsTheTable() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue, upTo: "v9")
        try Schema.migrator.migrate(queue)
        try queue.read { db in
            XCTAssertTrue(try db.tableExists("views"))
            XCTAssertTrue(try db.viewExists("live_views"))
        }
    }
}
