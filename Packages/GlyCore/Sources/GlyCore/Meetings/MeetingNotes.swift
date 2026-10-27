import Foundation
import GRDB

/// Which notes document an appointment has (meeting-pages N1, N2).
public struct MeetingNotesRef: Equatable {
    public enum Target: Equatable {
        /// A recurring meeting's series document; `ruleID` nil until the series rule exists.
        case series(ruleID: String?)
        /// A one-off meeting's own document (the occurrence's annotation row).
        case occurrence(key: String)
    }
    public let target: Target
    /// The event_note row holding the notes, if any (for a one-off it may exist for a blocking override only).
    public let itemID: String?
    public let body: String
    public var hasNotes: Bool { !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public enum MeetingNotes {
    /// The notes document of an appointment: its series' for recurring meetings (the rule follows splits), else its own.
    public static func document(for a: Appointment, db: Database) throws -> MeetingNotesRef {
        if a.isRecurring {
            let rule = try AnnotationQueries.seriesRules(db).first { $0.matches(a) }
            let row = try rule.flatMap { r in
                try Row.fetchOne(db, sql: "SELECT id, body FROM live_items WHERE kind = 'event_note' AND series_rule = ? ORDER BY created_at LIMIT 1",
                                 arguments: [r.id])
            }
            return MeetingNotesRef(target: .series(ruleID: rule?.id), itemID: row?["id"], body: row?["body"] ?? "")
        }
        let key = a.identity.occurrenceKey
        let row = try Row.fetchOne(db, sql: "SELECT id, body FROM live_items WHERE kind = 'event_note' AND event_key = ? LIMIT 1", arguments: [key])
        return MeetingNotesRef(target: .occurrence(key: key), itemID: row?["id"], body: row?["body"] ?? "")
    }
}

/// A stored notes document with the meeting snapshot it keeps (the page opened from search, tags, backlinks).
public struct MeetingNotesItem: Equatable {
    public let id: String
    public let title: String
    public let body: String
    public let tags: [String]
    public let calendarID: String?
    public let start: Date?
    public let end: Date?
    public let organizer: String?
    /// active, cancelled, gone, ambiguous (occurrence rows); series documents stay active.
    public let state: String
    public let seriesRuleID: String?
    public let occurrenceKey: String?
    public let deleted: Bool
}

/// Which meetings have notes, for the day view's icons (one observation for all rows).
public struct MeetingNotesMarks: Equatable, Sendable {
    public var occurrenceKeys: Set<String> = []
    public var rules: [SeriesRule] = []
    public init() {}

    public func hasNotes(_ a: Appointment) -> Bool {
        if a.isRecurring, rules.contains(where: { $0.matches(a) }) { return true }
        return occurrenceKeys.contains(a.identity.occurrenceKey)
    }
}

extension MeetingNotes {
    public static func item(_ db: Database, id: String) throws -> MeetingNotesItem? {
        guard let r = try Row.fetchOne(db, sql: "SELECT * FROM items WHERE id = ? AND kind = 'event_note'", arguments: [id]) else { return nil }
        return MeetingNotesItem(id: id, title: r["title"], body: r["body"] ?? "", tags: try TaskQueries.tagsByItem(db, ids: [id])[id] ?? [],
                                calendarID: r["event_calendar"], start: r["event_start"], end: r["event_end"], organizer: r["event_organizer"],
                                state: r["event_state"] ?? "active", seriesRuleID: r["series_rule"], occurrenceKey: r["event_key"],
                                deleted: (r["deleted_at"] as Date?) != nil)
    }

    public static func marks(_ db: Database) throws -> MeetingNotesMarks {
        var m = MeetingNotesMarks()
        let withNotes = "FROM live_items WHERE kind = 'event_note' AND body != ''"
        m.occurrenceKeys = Set(try String.fetchAll(db, sql: "SELECT event_key \(withNotes) AND event_key IS NOT NULL"))
        let ruleIDs = Set(try String.fetchAll(db, sql: "SELECT series_rule \(withNotes) AND series_rule IS NOT NULL"))
        m.rules = try AnnotationQueries.seriesRules(db).filter { ruleIDs.contains($0.id) }
        return m
    }
}
