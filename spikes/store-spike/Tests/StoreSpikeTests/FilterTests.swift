import GRDB
import XCTest
@testable import StoreSpike

/// In-memory brute-force model of the live data, as an independent oracle for the SQL compiler.
struct Oracle {
    struct Item { let id, kind: String; let status, priority: String?; let due: Date? }
    var items: [Item] = []
    var tagsByItem: [String: [String]] = [:]
    var props: [String: [(key: String, num: Double?, date: Date?)]] = [:]

    init(_ db: Database) throws {
        for r in try Row.fetchAll(db, sql: "SELECT id, kind, status, priority, due FROM items WHERE deleted_at IS NULL") {
            items.append(Item(id: r["id"], kind: r["kind"], status: r["status"], priority: r["priority"], due: r["due"]))
        }
        for r in try Row.fetchAll(db, sql: """
            SELECT it.item_id, t.name FROM item_tags it JOIN tags t ON t.id = it.tag_id
            WHERE it.deleted_at IS NULL AND t.deleted_at IS NULL
            """) {
            tagsByItem[r["item_id"], default: []].append(r["name"])
        }
        for r in try Row.fetchAll(db, sql: """
            SELECT pv.owner_id, k.name, pv.number_value, pv.date_value FROM property_values pv
            JOIN property_keys k ON k.id = pv.key_id WHERE pv.deleted_at IS NULL AND k.deleted_at IS NULL
            """) {
            props[r["owner_id"], default: []].append((r["name"], r["number_value"], r["date_value"]))
        }
    }
    func hasTag(_ i: Item, under name: String, prefixOnly: Bool) -> Bool {
        (tagsByItem[i.id] ?? []).contains { $0.hasPrefix(name + "/") || (!prefixOnly && $0 == name) }
    }
    func ids(_ pred: (Item) -> Bool) -> Set<String> { Set(items.filter(pred).map(\.id)) }
}

final class FilterTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
    var today: Date { Calendar(identifier: .gregorian).startOfDay(for: now) }
    func days(_ n: Int) -> Date { Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: today)! }
    let rank = ["none": 0, "low": 1, "normal": 2, "high": 3, "urgent": 4]

    func run(_ filter: String, _ db: Database) throws -> (ids: Set<String>, ms: Double) {
        _ = try db.query(filter, now: now)                     // warm-up (statement cache, pages)
        var best = Double.infinity
        var result: [Row] = []
        for _ in 0..<5 {
            let t0 = Date()
            result = try db.query(filter, now: now)
            best = min(best, Date().timeIntervalSince(t0) * 1000)
        }
        print(String(format: "filter %-60@ %5d rows  %6.2f ms", filter as NSString, result.count, best))
        return (Set(result.map { $0["id"] as String }), best)
    }

    func check(_ filter: String, _ pred: (Oracle, Oracle.Item) -> Bool) throws {
        try Fixture.store.db.read { db in
            let oracle = try Oracle(db)
            let expected = oracle.ids { pred(oracle, $0) }
            let (got, ms) = try run(filter, db)
            XCTAssertFalse(expected.isEmpty, "filter should match something: \(filter)")
            XCTAssertEqual(got, expected, filter)
            XCTAssertLessThan(ms, 50, "too slow: \(filter)")
        }
    }

    func testPersonWithUpcomingReview() throws {
        try check("person/* AND next_review < +30d") { o, i in
            o.hasTag(i, under: "person", prefixOnly: true)
                && (o.props[i.id] ?? []).contains { $0.key == "next_review" && $0.date != nil && $0.date! < self.days(30) }
        }
    }

    func testOpenHighPriorityTasks() throws {
        try check("task AND status = open AND priority >= high") { _, i in
            i.kind == "task" && i.status == "open" && (self.rank[i.priority ?? ""] ?? -1) >= 3
        }
    }

    func testProjectSubtreeWithEffort() throws {
        try check("tag:project AND effort > 50") { o, i in
            o.hasTag(i, under: "project", prefixOnly: false)
                && (o.props[i.id] ?? []).contains { $0.key == "effort" && ($0.num ?? -1) > 50 }
        }
    }

    func testOverdueOneOnOneOrPersonTasks() throws {
        try check("task AND (1-1 OR person/*) AND NOT status = done AND due < today") { o, i in
            i.kind == "task"
                && ((o.tagsByItem[i.id] ?? []).contains("1-1") || o.hasTag(i, under: "person", prefixOnly: true))
                && i.status != nil && i.status != "done"
                && i.due != nil && i.due! < self.today
        }
    }

    func testParserRejectsGarbage() {
        XCTAssertThrowsError(try parseFilter("person/* AND"))
        XCTAssertThrowsError(try parseFilter("(task"))
        XCTAssertThrowsError(try Fixture.store.db.read { try $0.query("nonexistent_key > 3") })
    }
}
