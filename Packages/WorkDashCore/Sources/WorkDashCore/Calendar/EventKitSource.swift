import CoreGraphics
import EventKit
import Foundation

/// The real calendar source. All EventKit types stay inside this file.
public final class EventKitSource: EventSource {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var debounce: DispatchWorkItem?
    private var refreshTimer: Timer?
    public var onChange: (() -> Void)?

    public init(refreshInterval: TimeInterval = 300) {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.scheduleChange()
        }
        refreshSources()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in self?.refreshSources() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        refreshTimer?.invalidate()
    }

    /// Changes arrive in bursts (one per account/calendar): coalesce them (300 ms).
    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    public var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .writeOnly: return .writeOnly
        case .fullAccess: return .fullAccess
        @unknown default: return .denied
        }
    }

    public func requestAccess() async -> Bool {
        if authorization == .fullAccess { return true }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        if granted { store.reset() }
        return granted
    }

    public func calendars() -> [CalendarInfo] {
        guard authorization.canRead else { return [] }
        return store.calendars(for: .event).map { c in
            CalendarInfo(id: c.calendarIdentifier, title: c.title, sourceID: c.source.sourceIdentifier,
                         sourceTitle: c.source.title, colorHex: Self.hex(c.cgColor))
        }.sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    public func appointments(overlapping interval: DateInterval, calendarIDs: Set<String>) -> [Appointment] {
        guard authorization.canRead, !calendarIDs.isEmpty else { return [] }
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate).map { e in
            let (title, cancelled) = CancellationRule.apply(title: e.title ?? "", statusCancelled: e.status == .canceled)
            let occurrence = e.occurrenceDate ?? e.startDate!
            let calendarID = e.calendar.calendarIdentifier
            let identity = AppointmentIdentity.from(externalID: e.calendarItemExternalIdentifier ?? e.eventIdentifier ?? UUID().uuidString,
                                                    occurrenceDate: occurrence, calendarID: calendarID)
            return Appointment(
                id: "\(calendarID)|\(e.eventIdentifier ?? UUID().uuidString)|\(occurrence.timeIntervalSinceReferenceDate)",
                calendarID: calendarID, title: title, start: e.startDate, end: e.endDate,
                isAllDay: e.isAllDay, isCancelled: cancelled, location: e.location,
                organizer: e.organizer?.name, attendees: (e.attendees ?? []).compactMap(\.name),
                lastModified: e.lastModifiedDate, identity: identity,
                availability: Self.availability(e.availability), myStatus: Self.myStatus(e.attendees),
                isOrganizer: e.organizer?.isCurrentUser ?? false,
                isRecurring: e.hasRecurrenceRules || e.isDetached)
        }
    }

    static func availability(_ a: EKEventAvailability) -> Availability {
        switch a {
        case .busy: return .busy
        case .free: return .free
        case .tentative: return .tentative
        case .unavailable: return .unavailable
        case .notSupported: return .unknown
        @unknown default: return .unknown
        }
    }

    static func myStatus(_ attendees: [EKParticipant]?) -> ParticipationStatus {
        guard let attendees, !attendees.isEmpty else { return .none }
        guard let me = attendees.first(where: \.isCurrentUser) else { return .none }
        switch me.participantStatus {
        case .accepted, .completed, .inProcess: return .accepted
        case .declined: return .declined
        case .tentative, .delegated: return .tentative
        case .pending: return .pending
        // Exchange reports .unknown for many meetings (probe, design Q1): no information, availability decides.
        case .unknown: return .none
        @unknown default: return .none
        }
    }

    public func refreshSources() {
        store.refreshSourcesIfNecessary()
    }

    static func hex(_ color: CGColor?) -> String {
        guard let color, let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let c = rgb.components, c.count >= 3 else { return "#888888" }
        return String(format: "#%02X%02X%02X", Int(round(c[0] * 255)), Int(round(c[1] * 255)), Int(round(c[2] * 255)))
    }
}
