import Foundation

/// A calendar from the system calendar store (no EventKit types outside the adapter).
public struct CalendarInfo: Identifiable, Hashable {
    public let id: String            // calendarIdentifier (device-local; fine for Mac-only UI preferences)
    public let title: String
    public let sourceID: String      // account
    public let sourceTitle: String   // e.g. "Exchange", "iCloud"
    public let colorHex: String      // "#RRGGBB"
    public init(id: String, title: String, sourceID: String, sourceTitle: String, colorHex: String) {
        self.id = id; self.title = title; self.sourceID = sourceID; self.sourceTitle = sourceTitle; self.colorHex = colorHex
    }
}

/// One occurrence of an appointment, read-only.
public struct Appointment: Identifiable, Hashable {
    public let id: String            // unique per occurrence within this process
    public let calendarID: String
    public let title: String         // display title ("Canceled:" prefix stripped)
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let isCancelled: Bool
    public let location: String?
    public let organizer: String?
    public let attendees: [String]
    public let lastModified: Date?

    public init(id: String, calendarID: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                isCancelled: Bool = false, location: String? = nil, organizer: String? = nil, attendees: [String] = [],
                lastModified: Date? = nil) {
        self.id = id; self.calendarID = calendarID; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.isCancelled = isCancelled; self.location = location; self.organizer = organizer
        self.attendees = attendees; self.lastModified = lastModified
    }
}

public enum CalendarAuthorization: Equatable {
    case notDetermined, denied, restricted, writeOnly, fullAccess
    public var canRead: Bool { self == .fullAccess }
}

/// Source of calendars and appointments. Real: `EventKitSource`; tests: `FakeEventSource`.
public protocol EventSource: AnyObject {
    var authorization: CalendarAuthorization { get }
    /// Asks the system for full access if not determined yet. Returns whether reading is allowed.
    func requestAccess() async -> Bool
    func calendars() -> [CalendarInfo]
    /// Appointments overlapping `interval` in the given calendars.
    func appointments(overlapping interval: DateInterval, calendarIDs: Set<String>) -> [Appointment]
    /// Called (debounced) when the system calendar changed.
    var onChange: (() -> Void)? { get set }
    /// Nudges the system to fetch remote changes (Exchange, CalDAV).
    func refreshSources()
}

/// Cancellation rule (specs/calendar-sources "Cancelled appointments stay visible").
public enum CancellationRule {
    static let prefixes = ["canceled:", "cancelled:", "abgesagt:"]

    /// - Returns: display title (prefix stripped) and whether the appointment counts as cancelled.
    public static func apply(title: String, statusCancelled: Bool) -> (title: String, isCancelled: Bool) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        for p in prefixes where trimmed.lowercased().hasPrefix(p) {
            let rest = trimmed.dropFirst(p.count).trimmingCharacters(in: .whitespaces)
            return (rest.isEmpty ? trimmed : rest, true)
        }
        return (trimmed, statusCancelled)
    }
}

/// In-memory source for tests and previews.
public final class FakeEventSource: EventSource {
    public var authorization: CalendarAuthorization
    public var calendarList: [CalendarInfo]
    public var events: [Appointment]
    public var onChange: (() -> Void)?
    public private(set) var refreshCount = 0

    public init(authorization: CalendarAuthorization = .fullAccess, calendars: [CalendarInfo] = [], events: [Appointment] = []) {
        self.authorization = authorization; self.calendarList = calendars; self.events = events
    }
    public func requestAccess() async -> Bool { authorization.canRead }
    public func calendars() -> [CalendarInfo] { calendarList }
    public func appointments(overlapping interval: DateInterval, calendarIDs: Set<String>) -> [Appointment] {
        events.filter { calendarIDs.contains($0.calendarID) && $0.start < interval.end && $0.end > interval.start }
    }
    public func refreshSources() { refreshCount += 1 }
    /// Simulates a system calendar change.
    public func change(_ mutate: (FakeEventSource) -> Void) { mutate(self); onChange?() }
}
