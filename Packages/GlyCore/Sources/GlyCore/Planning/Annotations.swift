import Foundation
import GRDB

/// What gly stores about an appointment it annotates (specs/appointment-annotations "Annotation life cycle").
public struct AppointmentSnapshot: Codable, Equatable, Hashable {
    public var calendarID: String
    public var baseID: String
    public var originalStart: Date
    public var title: String
    public var start: Date
    public var end: Date
    public var organizer: String?

    public init(calendarID: String, baseID: String, originalStart: Date, title: String, start: Date, end: Date, organizer: String?) {
        self.calendarID = calendarID; self.baseID = baseID; self.originalStart = originalStart
        self.title = title; self.start = start; self.end = end; self.organizer = organizer
    }

    public init(_ a: Appointment) {
        self.init(calendarID: a.identity.calendarID, baseID: a.identity.baseID, originalStart: a.identity.originalStart,
                  title: a.title, start: a.start, end: a.end, organizer: a.organizer)
    }

    var identity: AppointmentIdentity { AppointmentIdentity(calendarID: calendarID, baseID: baseID, originalStart: originalStart) }
    public var key: String { identity.occurrenceKey }
    public var seriesKey: String { identity.seriesKey }
}

public enum BlockingScope: String, Codable { case occurrence, series }

/// A stored annotation of one occurrence.
public struct Annotation: Equatable, Identifiable {
    public let id: String
    public let key: String
    public let title: String
    public let calendarID: String
    public let start: Date
    public let end: Date
    public let organizer: String?
    public let state: String
    public let blocking: BlockingOverride?
}

/// A blocking rule for a whole series; follows series splits through `baseIDs`.
public struct SeriesRule: Equatable, Identifiable {
    public let id: String
    public let calendarID: String
    public let title: String
    public let organizer: String?
    public let baseIDs: [String]
    public let blocking: BlockingOverride?

    /// Same series as the appointment a snapshot was taken of (see `matches(_:)`).
    public func matches(_ s: AppointmentSnapshot) -> Bool {
        guard s.calendarID == calendarID else { return false }
        if baseIDs.contains(s.baseID) { return true }
        return TagName.key(for: s.title) == TagName.key(for: title) && (s.organizer ?? "") == (organizer ?? "")
    }

    /// Same series (by id), or its continuation after a split (same calendar, title and organizer).
    public func matches(_ a: Appointment) -> Bool {
        guard a.identity.calendarID == calendarID else { return false }
        if baseIDs.contains(a.identity.baseID) { return true }
        return TagName.key(for: a.title) == TagName.key(for: title) && (a.organizer ?? "") == (organizer ?? "")
    }
}

/// Overrides that apply to appointments (design Q5): occurrence overrides by key, series rules.
public struct BlockingOverrides: Equatable {
    public var occurrence: [String: BlockingOverride] = [:]
    public var series: [SeriesRule] = []
    public init(occurrence: [String: BlockingOverride] = [:], series: [SeriesRule] = []) { self.occurrence = occurrence; self.series = series }

    public func classify(_ a: Appointment) -> (weight: BlockingWeight, reason: BlockingReason) {
        Blocking.classify(a, occurrence: occurrence[a.identity.occurrenceKey],
                          series: series.first { $0.matches(a) && $0.blocking != nil }?.blocking)
    }

    public func busy(_ appointments: [Appointment]) -> [(interval: DateInterval, weight: BlockingWeight)] {
        appointments.map { (interval: $0.interval, weight: classify($0).weight) }
    }
}

public enum AnnotationQueries {
    public static func annotations(_ db: Database, from: Date? = nil, to: Date? = nil) throws -> [Annotation] {
        var sql = "SELECT * FROM live_items WHERE kind = 'event_note' AND event_key IS NOT NULL"
        var args: [DatabaseValueConvertible] = []
        if let from { sql += " AND event_start >= ?"; args.append(from) }
        if let to { sql += " AND event_start < ?"; args.append(to) }
        return try Row.fetchAll(db, sql: sql + " ORDER BY event_start", arguments: StatementArguments(args)).map(annotation)
    }

    static func annotation(_ r: Row) -> Annotation {
        Annotation(id: r["id"], key: r["event_key"], title: r["title"], calendarID: r["event_calendar"] ?? "",
                   start: r["event_start"], end: r["event_end"], organizer: r["event_organizer"],
                   state: r["event_state"] ?? "active", blocking: (r["blocking"] as String?).flatMap(BlockingOverride.init(rawValue:)))
    }

    public static func seriesRules(_ db: Database) throws -> [SeriesRule] {
        try Row.fetchAll(db, sql: "SELECT * FROM live_series_rules").map { r in
            let ids = (try? JSONDecoder().decode([String].self, from: Data((r["base_ids"] as String? ?? "[]").utf8))) ?? []
            return SeriesRule(id: r["id"], calendarID: r["calendar_id"], title: r["title"], organizer: r["organizer"],
                              baseIDs: ids, blocking: (r["blocking"] as String?).flatMap(BlockingOverride.init(rawValue:)))
        }
    }

    /// Overrides in effect: occurrence overrides of active/cancelled annotations (not ambiguous or gone), and series rules.
    public static func overrides(_ db: Database) throws -> BlockingOverrides {
        var occurrence: [String: BlockingOverride] = [:]
        for a in try annotations(db) where ["active", "cancelled"].contains(a.state) {
            if let b = a.blocking { occurrence[a.key] = b }
        }
        return BlockingOverrides(occurrence: occurrence, series: try seriesRules(db))
    }

    static func encodeIDs(_ ids: [String]) -> String {
        String(decoding: (try? JSONEncoder().encode(ids)) ?? Data("[]".utf8), as: UTF8.self)
    }
}
