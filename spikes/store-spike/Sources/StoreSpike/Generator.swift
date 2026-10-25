// Spike 2 (foundation-spikes): realistic volume generator. Throwaway code.
// Bulk-inserts directly (no change log): it's seed data, not user edits.
import Foundation
import GRDB

/// Deterministic RNG so runs are comparable.
public struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public struct GeneratorConfig {
    public var items = 10_000
    public var tags = 500
    public var propertyValues = 50_000
    public var links = 5_000
    public var recurrences = 50
    public var seed: UInt64 = 42
    public var now = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
    public init() {}
}

public struct GeneratedStats: Equatable {
    public var items = 0, tags = 0, itemTags = 0, links = 0, propertyKeys = 0, propertyValues = 0, recurrences = 0
}

let words = ["Budget", "Budgetfreigabe", "Planung", "Übergabe", "Prüfung", "Telemetrie", "Pipeline", "Review",
             "Architektur", "Migration", "Kunde", "Rückmeldung", "Lasttest", "Sprint", "Retro", "Ziele", "Karriere",
             "Feedback", "Entscheidung", "Rollout", "Metriken", "Logs", "Traces", "Kosten", "Angebot", "Vertrag",
             "Onboarding", "Schulung", "Präsentation", "Workshop", "Roadmap", "Risiko", "Incident", "Postmortem",
             "Gehalt", "Beförderung", "Urlaub", "Zeitplan", "Abstimmung", "Freigabe"]

let propertyKeySpecs: [(String, String)] = [
    ("role", "text"), ("team", "text"), ("since", "date"), ("next_review", "date"), ("status", "text"),
    ("deadline", "date"), ("effort", "number"), ("budget_eur", "number"), ("url", "text"), ("active", "bool"),
    ("owner", "link"), ("customer", "text"), ("rating", "number"), ("started", "date"), ("ended", "date"),
    ("location", "text"), ("level", "number"), ("billable", "bool"), ("topics", "list"), ("ticket", "text"),
]

extension Database {
    @discardableResult
    public func generate(_ cfg: GeneratorConfig = GeneratorConfig()) throws -> GeneratedStats {
        var rng = SplitMix64(seed: cfg.seed)
        var stats = GeneratedStats()
        let w = "generator"
        let now = cfg.now
        func pick<T>(_ a: [T]) -> T { a[Int.random(in: 0..<a.count, using: &rng)] }
        func uuid() -> String {
            var b = [UInt8](repeating: 0, count: 16)
            for i in 0..<16 { b[i] = UInt8.random(in: 0...255, using: &rng) }
            return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])).uuidString
        }
        func day(_ offset: Int) -> Date { now.addingTimeInterval(Double(offset) * 86_400) }
        func phrase(_ n: Int) -> String { (0..<n).map { _ in pick(words) }.joined(separator: " ") }

        // Tags: hierarchical prefixes, a few flat ones.
        var tagIds: [String] = []
        var personTags: [String] = []
        let tagStmt = try makeStatement(sql: "INSERT INTO tags (id, created_at, modified_at, modified_by, name, page_body) VALUES (?, ?, ?, ?, ?, ?)")
        var names = Set<String>()
        while tagIds.count < cfg.tags {
            let r = Int.random(in: 0..<100, using: &rng)
            let name: String
            switch r {
            case 0..<25: name = "person/p\(Int.random(in: 0..<200, using: &rng))"
            case 25..<45: name = "project/\(pick(words).lowercased())\(Int.random(in: 0..<30, using: &rng))"
            case 45..<60: name = "project/\(pick(words).lowercased())/\(pick(words).lowercased())"
            case 60..<85: name = "topic/\(pick(words).lowercased())/\(Int.random(in: 0..<20, using: &rng))"
            default: name = "\(pick(words).lowercased())\(Int.random(in: 0..<50, using: &rng))"
            }
            guard names.insert(name).inserted else { continue }
            let id = uuid()
            try tagStmt.execute(arguments: [id, now, now, w, name, "Seite für \(name): \(phrase(12))"])
            tagIds.append(id)
            if name.hasPrefix("person/") { personTags.append(id) }
        }
        try execute(sql: "INSERT INTO tags (id, created_at, modified_at, modified_by, name) VALUES (?, ?, ?, ?, '1-1')", arguments: [uuid(), now, now, w])
        stats.tags = tagIds.count + 1

        // Recurrences
        var recIds: [String] = []
        for i in 0..<cfg.recurrences {
            let id = uuid()
            try execute(sql: """
                INSERT INTO recurrences (id, created_at, modified_at, modified_by, template_title, rule, model, missed_policy)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [id, now, now, w, "Wiederkehrend \(i): \(phrase(2))", "FREQ=WEEKLY",
                                 pick(["fixed", "after_completion", "after_event"]), pick(["pile_up", "replace"])])
            recIds.append(id)
        }
        stats.recurrences = recIds.count

        // Items: 50% task, 38% info, 9% event_note, 3% local_event
        var itemIds: [String] = []
        let itemStmt = try makeStatement(sql: """
            INSERT INTO items (id, created_at, modified_at, modified_by, deleted_at, kind, title, body, status, priority, due,
                               recurrence_id, event_key, event_status, start_at, end_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        let itStmt = try makeStatement(sql: "INSERT INTO item_tags (id, created_at, modified_at, modified_by, item_id, tag_id) VALUES (?, ?, ?, ?, ?, ?)")
        for i in 0..<cfg.items {
            let id = uuid()
            let r = Int.random(in: 0..<100, using: &rng)
            let kind = r < 50 ? "task" : r < 88 ? "info" : r < 97 ? "event_note" : "local_event"
            let created = day(-Int.random(in: 0..<720, using: &rng))
            let deleted: Date? = Int.random(in: 0..<100, using: &rng) < 3 ? now : nil   // 3% tombstones
            var status: String?, priority: String?, due: Date?, rec: String?, eventKey: String?, eventStatus: String?, start: Date?, end: Date?
            if kind == "task" {
                status = pick(["inbox", "open", "open", "open", "snoozed", "done", "done", "dropped"])
                priority = pick(["none", "low", "normal", "normal", "high", "urgent"])
                due = Int.random(in: 0..<100, using: &rng) < 60 ? day(Int.random(in: -60..<90, using: &rng)) : nil
                rec = Int.random(in: 0..<100, using: &rng) < 5 ? pick(recIds) : nil
            } else if kind == "event_note" {
                eventKey = "Exchange/Kalender/\(uuid())@\(ISO8601DateFormatter().string(from: day(Int.random(in: -300..<60, using: &rng))))"
                eventStatus = pick(["active", "active", "active", "cancelled", "gone"])
            } else if kind == "local_event" {
                start = day(Int.random(in: -30..<60, using: &rng))
                end = start!.addingTimeInterval(3600)
            }
            let title = i == 0 ? "Budgetfreigabe Lasttests Q1" : phrase(Int.random(in: 2...6, using: &rng))
            let body = phrase(Int.random(in: 10...80, using: &rng))
            try itemStmt.execute(arguments: [id, created, created, w, deleted, kind, title, body, status, priority, due,
                                             rec, eventKey, eventStatus, start, end])
            itemIds.append(id)
            // 0-4 tags per item, persons more likely on tasks/event notes
            var used = Set<String>()
            for _ in 0..<Int.random(in: 0...4, using: &rng) {
                let t = (kind != "info" && Int.random(in: 0..<3, using: &rng) == 0 && !personTags.isEmpty) ? pick(personTags) : pick(tagIds)
                guard used.insert(t).inserted else { continue }
                try itStmt.execute(arguments: [uuid(), created, created, w, id, t])
                stats.itemTags += 1
            }
        }
        stats.items = itemIds.count

        // Property keys + typed values
        var keys: [(String, String)] = []
        for (name, type) in propertyKeySpecs {
            let id = uuid()
            try execute(sql: "INSERT INTO property_keys (id, created_at, modified_at, modified_by, name, type) VALUES (?, ?, ?, ?, ?, ?)",
                        arguments: [id, now, now, w, name, type])
            keys.append((id, type))
        }
        stats.propertyKeys = keys.count
        let pvStmt = try makeStatement(sql: """
            INSERT INTO property_values (id, created_at, modified_at, modified_by, owner_id, owner_kind, key_id,
                                         text_value, number_value, date_value, bool_value, ref_value)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        for _ in 0..<cfg.propertyValues {
            let onTag = Int.random(in: 0..<10, using: &rng) == 0
            let owner = onTag ? pick(tagIds) : pick(itemIds)
            let (keyId, type) = pick(keys)
            var text: String?, num: Double?, date: Date?, bool: Bool?, ref: String?
            switch type {
            case "text": text = pick(words)
            case "number": num = Double(Int.random(in: 0...100, using: &rng))
            case "date": date = day(Int.random(in: -365..<365, using: &rng))
            case "bool": bool = Bool.random(using: &rng)
            case "list": text = "[\"\(pick(words))\",\"\(pick(words))\"]"
            default: ref = pick(itemIds)
            }
            try pvStmt.execute(arguments: [uuid(), now, now, w, owner, onTag ? "tag" : "item", keyId, text, num, date, bool, ref])
        }
        stats.propertyValues = cfg.propertyValues

        let linkStmt = try makeStatement(sql: "INSERT INTO links (id, created_at, modified_at, modified_by, from_id, to_id, type) VALUES (?, ?, ?, ?, ?, ?, ?)")
        for _ in 0..<cfg.links {
            try linkStmt.execute(arguments: [uuid(), now, now, w, pick(itemIds), pick(itemIds), pick([nil, "prep-for", "follow-up-of", "minutes-of", "about"])])
        }
        stats.links = cfg.links
        return stats
    }
}
