import Foundation

/// Tracks, per calendar account, when gly last saw a change from it (design L7).
///
/// EventKit exposes no per-account sync time. On every system calendar change, the tracker
/// fingerprints each account's appointments in a window around now; only accounts whose
/// fingerprint differs get a new "last change seen" time. Approximate by design: it measures
/// changes seen, not sync attempts.
public final class SourceActivityTracker {
    public struct Status: Equatable {
        public let sourceID: String
        public let sourceTitle: String
        /// nil = no change seen since launch.
        public let lastChangeSeen: Date?
    }

    private let source: EventSource
    private let windowDays: Int
    private var fingerprints: [String: Int] = [:]
    private var lastSeen: [String: Date] = [:]
    private var titles: [String: String] = [:]

    public init(source: EventSource, windowDays: Int = 30) {
        self.source = source
        self.windowDays = windowDays
    }

    /// Takes the baseline (call on launch, after access was granted).
    public func baseline(now: Date = Date()) {
        fingerprints = currentFingerprints(now: now)
    }

    /// Call after each system calendar change. Returns the accounts that changed.
    @discardableResult
    public func recordChange(now: Date = Date()) -> Set<String> {
        let current = currentFingerprints(now: now)
        var changed = Set<String>()
        for (sourceID, fp) in current where fingerprints[sourceID] != fp {
            changed.insert(sourceID)
        }
        // An account whose events all disappeared also changed.
        for sourceID in fingerprints.keys where current[sourceID] == nil { changed.insert(sourceID) }
        for id in changed { lastSeen[id] = now }
        fingerprints = current
        return changed
    }

    public func statuses() -> [Status] {
        let ids = Set(titles.keys)
        return ids.map { Status(sourceID: $0, sourceTitle: titles[$0] ?? $0, lastChangeSeen: lastSeen[$0]) }
            .sorted { $0.sourceTitle < $1.sourceTitle }
    }

    private func currentFingerprints(now: Date) -> [String: Int] {
        let calendars = source.calendars()
        var sourceOf: [String: String] = [:]
        for c in calendars {
            sourceOf[c.id] = c.sourceID
            titles[c.sourceID] = c.sourceTitle
        }
        let window = DateInterval(start: now.addingTimeInterval(-Double(windowDays) * 86_400),
                                  end: now.addingTimeInterval(Double(windowDays) * 86_400))
        var hashers: [String: Hasher] = [:]
        var counts: [String: Int] = [:]
        // Sorted for a stable fingerprint independent of fetch order.
        for a in source.appointments(overlapping: window, calendarIDs: Set(sourceOf.keys)).sorted(by: { $0.id < $1.id }) {
            guard let sid = sourceOf[a.calendarID] else { continue }
            var h = hashers[sid] ?? Hasher()
            h.combine(a.id); h.combine(a.title); h.combine(a.start); h.combine(a.end)
            h.combine(a.isCancelled); h.combine(a.lastModified)
            hashers[sid] = h
            counts[sid, default: 0] += 1
        }
        var result: [String: Int] = [:]
        for sid in Set(sourceOf.values) {
            var h = hashers[sid] ?? Hasher()
            h.combine(counts[sid] ?? 0)
            result[sid] = h.finalize()
        }
        return result
    }
}
