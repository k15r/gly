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
