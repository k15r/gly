import AppKit
import Foundation
import Observation
import WorkDashCore

/// Calendar state for the app: permission, calendar list, visibility, appointments of the shown day,
/// per-account "last change seen" (specs/calendar-sources).
@MainActor
@Observable
final class CalendarModel {
    private(set) var authorization: CalendarAuthorization = .notDetermined
    private(set) var calendars: [CalendarInfo] = []
    private(set) var appointments: [Appointment] = []
    private(set) var sourceStatuses: [SourceActivityTracker.Status] = []
    /// Bumped on every system calendar change so views can refresh.
    private(set) var changeCounter = 0

    private(set) var shownDay: LocalDay = LocalDay(date: Date())
    private let source: EventSource
    private let tracker: SourceActivityTracker
    private let settings: SharedSettings

    /// Hidden calendar IDs. A stored property so SwiftUI observes it; persisted to the shared settings
    /// on change, where the agent reads them for `get_schedule` (design M7).
    private(set) var hiddenIDs: Set<String> {
        didSet { settings.hiddenCalendarIDs = hiddenIDs }
    }

    init(source: EventSource = EventKitSource(), settings: SharedSettings = .shared()) {
        self.source = source
        self.settings = settings
        settings.migrate(from: .standard)
        hiddenIDs = settings.hiddenCalendarIDs
        tracker = SourceActivityTracker(source: source)
        source.onChange = { [weak self] in
            Task { @MainActor in self?.systemCalendarChanged() }
        }
    }

    var visibleIDs: Set<String> { Set(calendars.map(\.id)).subtracting(hiddenIDs) }

    /// Calendars grouped by account, for the calendar list.
    var calendarsBySource: [(source: String, calendars: [CalendarInfo])] {
        Dictionary(grouping: calendars, by: \.sourceTitle).map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.source < $1.source }
    }

    func start() async {
        authorization = source.authorization
        if authorization == .notDetermined {
            _ = await source.requestAccess()
            authorization = source.authorization
        }
        reloadCalendars()
        tracker.baseline()
        sourceStatuses = tracker.statuses()
        reloadDay()
    }

    func show(day: LocalDay) {
        shownDay = day
        reloadDay()
    }

    func setVisible(_ calendarID: String, _ visible: Bool) {
        if visible { hiddenIDs.remove(calendarID) } else { hiddenIDs.insert(calendarID) }
        reloadDay()
    }

    func isVisible(_ calendarID: String) -> Bool { !hiddenIDs.contains(calendarID) }

    func calendar(for id: String) -> CalendarInfo? { calendars.first { $0.id == id } }

    func refreshSources() { source.refreshSources() }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func systemCalendarChanged() {
        authorization = source.authorization
        reloadCalendars()       // new calendars are visible by default: hidden is an explicit list
        tracker.recordChange()
        sourceStatuses = tracker.statuses()
        reloadDay()
        changeCounter += 1
    }

    private func reloadCalendars() {
        calendars = source.calendars()
    }

    private func reloadDay() {
        guard authorization.canRead else { appointments = []; return }
        appointments = source.appointments(overlapping: shownDay.interval(), calendarIDs: visibleIDs)
    }
}
