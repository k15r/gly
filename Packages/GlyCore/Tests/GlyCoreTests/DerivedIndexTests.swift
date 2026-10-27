import GRDB
import XCTest
@testable import GlyCore

final class DerivedIndexTests: XCTestCase {
    func snapshot(_ db: Database) throws -> [String] {
        let links = try Row.fetchAll(db, sql: "SELECT source_table, source_id, target_kind, target_id, missing_key, range_location, range_length FROM link_index ORDER BY source_id, range_location")
            .map { "\($0)" }
        let search = try Row.fetchAll(db, sql: "SELECT rowid, owner_id, kind, title, text FROM search_index ORDER BY rowid").map { "\($0)" }
        return links + ["--"] + search
    }

    /// The incrementally maintained indexes equal a fresh rebuild.
    func assertConsistent(_ queue: DatabaseQueue, file: StaticString = #filePath, line: UInt = #line) throws {
        try queue.write { db in
            let incremental = try snapshot(db)
            try DerivedIndex.rebuild(db)
            XCTAssertEqual(incremental, try snapshot(db), file: file, line: line)
        }
    }

    func testCreateEditDeleteUndoRedoStayConsistent() throws {
        let queue = try StoreFactory.openInMemory()
        let h = CommandHandler(writer: queue)
        guard case .ok(let a) = h.perform(.createTask(TaskDraft(title: "Target", tags: ["project/atlas"])), writer: "u"),
              let target = a.id else { return XCTFail() }
        guard case .ok(let b) = h.perform(.createTask(TaskDraft(title: "Source", body: "see [x](gly://item/\(target)) and [[Later]]")), writer: "u"),
              let source = b.id else { return XCTFail() }
        try assertConsistent(queue)
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM link_index WHERE source_id = ?", arguments: [source]) }, 2)

        _ = h.perform(.updateTask(id: source, TaskPatch(body: "only [[Later]]")), writer: "u")
        try assertConsistent(queue)
        _ = h.perform(.deleteTask(id: target), writer: "u")
        try assertConsistent(queue)
        _ = h.perform(.undo, writer: "u")
        try assertConsistent(queue)
        _ = h.perform(.undo, writer: "u")
        try assertConsistent(queue)
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM link_index WHERE source_id = ?", arguments: [source]) }, 2,
                       "undo restored the body and its links")
        _ = h.perform(.redo, writer: "u")
        try assertConsistent(queue)
    }

    func testSearchIndexHoldsPlainText() throws {
        let queue = try StoreFactory.openInMemory()
        let h = CommandHandler(writer: queue)
        _ = h.perform(.createTask(TaskDraft(title: "Budget", body: "[Überblick](gly://item/0E5A3C1D-2B4F-4A6E-9C8D-1F2E3D4C5B6A)")), writer: "u")
        let text = try queue.read { try String.fetchOne($0, sql: "SELECT text FROM search_index") }
        XCTAssertEqual(text, "Überblick")
        let hits = try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM search_index WHERE search_index MATCH 'uberblick'") }
        XCTAssertEqual(hits, 1, "diacritics removed")
    }
}
