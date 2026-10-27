import Foundation

/// The user's override for how an appointment counts for free time (specs/appointment-annotations).
public enum BlockingOverride: String, Codable, Hashable, CaseIterable, Sendable {
    case blocks, optional, ignore
}

/// How much of an appointment's time is taken from free time (specs/daily-planning "How appointments block time").
public enum BlockingWeight: String, Codable, Hashable {
    case blocks, maybe, free
    public var factor: Double { switch self { case .blocks: 1; case .maybe: 0.5; case .free: 0 } }
}

public enum BlockingReason: Equatable, Hashable {
    case automatic
    case occurrenceOverride
    case seriesOverride
}

public enum Blocking {
    /// Occurrence override first, then series override, then the automatic rules (design Q5).
    /// Unknown availability and missing participation count as busy and accepted (the safe side).
    public static func classify(_ a: Appointment, occurrence: BlockingOverride? = nil, series: BlockingOverride? = nil)
        -> (weight: BlockingWeight, reason: BlockingReason) {
        if let o = occurrence { return (weight(o), .occurrenceOverride) }
        if let s = series { return (weight(s), .seriesOverride) }
        return (automatic(a), .automatic)
    }

    static func weight(_ o: BlockingOverride) -> BlockingWeight {
        switch o { case .blocks: .blocks; case .optional: .maybe; case .ignore: .free }
    }

    static func automatic(_ a: Appointment) -> BlockingWeight {
        if a.isCancelled || a.myStatus == .declined { return .free }
        if a.availability == .free { return .free }
        if a.isAllDay { return a.availability == .unavailable || a.availability == .busy ? .blocks : .free }
        if a.myStatus == .tentative || a.myStatus == .pending || a.availability == .tentative { return .maybe }
        return .blocks
    }
}
