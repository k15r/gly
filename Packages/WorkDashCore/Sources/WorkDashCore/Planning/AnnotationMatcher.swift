import Foundation

/// An appointment as the calendar shows it now, for matching (snapshot + cancelled flag).
public struct ObservedAppointment: Codable, Equatable {
    public var snapshot: AppointmentSnapshot
    public var isCancelled: Bool
    public init(snapshot: AppointmentSnapshot, isCancelled: Bool) { self.snapshot = snapshot; self.isCancelled = isCancelled }
    public init(_ a: Appointment) { self.init(snapshot: AppointmentSnapshot(a), isCancelled: a.isCancelled) }
}

/// Keeps annotations attached to their appointments (foundation-spikes D4, design Q4).
public enum AnnotationMatcher {
    public enum Change: Equatable {
        /// Found (by key or a unique fuzzy match): new snapshot (and possibly new key), active or cancelled.
        case update(annotationID: String, to: ObservedAppointment)
        /// Several candidates: the user has to choose.
        case ambiguous(annotationID: String)
        /// Not in the calendar anymore.
        case gone(annotationID: String)
        /// A series rule follows a split: add this base id.
        case adoptBaseID(ruleID: String, baseID: String)
    }

    /// - Parameters:
    ///   - annotations: live annotations whose snapshot start lies in the window that `appointments` covers.
    ///   - appointments: everything the calendar has in that window.
    public static func reconcile(annotations: [Annotation], appointments: [ObservedAppointment], rules: [SeriesRule],
                                 calendar: Calendar = .current) -> [Change] {
        var changes: [Change] = []
        let byKey = Dictionary(appointments.map { ($0.snapshot.key, $0) }, uniquingKeysWith: { a, _ in a })
        let claimed = Set(annotations.map(\.key))
        for a in annotations {
            if let found = byKey[a.key] {
                let state = found.isCancelled ? "cancelled" : "active"
                if state != a.state || !same(found.snapshot, a) { changes.append(.update(annotationID: a.id, to: found)) }
                continue
            }
            let day = LocalDay(date: a.start, calendar: calendar)
            let candidates = appointments.filter { c in
                c.snapshot.calendarID == a.calendarID
                    && !claimed.contains(c.snapshot.key)
                    && TagName.key(for: c.snapshot.title) == TagName.key(for: a.title)
                    && (c.snapshot.organizer ?? "") == (a.organizer ?? "")
                    && (LocalDay(date: c.snapshot.start, calendar: calendar) == day || LocalDay(date: c.snapshot.originalStart, calendar: calendar) == day)
            }
            switch candidates.count {
            case 1: changes.append(.update(annotationID: a.id, to: candidates[0]))
            case 0: if a.state != "gone" { changes.append(.gone(annotationID: a.id)) }
            default: if a.state != "ambiguous" { changes.append(.ambiguous(annotationID: a.id)) }
            }
        }
        // Series rules adopt the base ids of split-off continuations (same calendar, title, organizer).
        var adopted = Set<String>()
        for r in rules {
            for c in appointments where c.snapshot.calendarID == r.calendarID && !r.baseIDs.contains(c.snapshot.baseID)
                && TagName.key(for: c.snapshot.title) == TagName.key(for: r.title) && (c.snapshot.organizer ?? "") == (r.organizer ?? "") {
                if adopted.insert(r.id + c.snapshot.baseID).inserted { changes.append(.adoptBaseID(ruleID: r.id, baseID: c.snapshot.baseID)) }
            }
        }
        return changes
    }

    static func same(_ s: AppointmentSnapshot, _ a: Annotation) -> Bool {
        s.key == a.key && s.title == a.title && s.start == a.start && s.end == a.end && s.organizer == a.organizer
    }
}
