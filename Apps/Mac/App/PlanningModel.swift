import Foundation
import GRDB
import Observation
import WorkDashCore

/// Planning state for the day view (planning-day-view): settings, overrides, upcoming tasks; computes free time and states.
@MainActor
@Observable
final class PlanningModel {
    @ObservationIgnored let settings: SharedSettings
    var hours: WorkingHours { didSet { settings.workingHours = hours; sizes = settings.effortSizes } }
    var horizon: Int { didSet { settings.horizonDays = horizon; observeUpcoming() } }
    private(set) var sizes: EffortSizes
    private(set) var overrides = BlockingOverrides()
    /// Annotations waiting for the user to pick their appointment.
    private(set) var ambiguous: [Annotation] = []
    private(set) var upcoming: [TaskItem] = []

    @ObservationIgnored private var store: ReadOnlyStore?
    @ObservationIgnored private var today = LocalDay(date: Date())
    @ObservationIgnored private var overridesObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var upcomingObservation: AnyDatabaseCancellable?

    init(settings: SharedSettings = .shared()) {
        self.settings = settings
        hours = settings.workingHours
        horizon = settings.horizonDays
        sizes = settings.effortSizes
    }

    func attach(_ store: ReadOnlyStore?) {
        guard let store, self.store !== store else { return }
        self.store = store
        overridesObservation = store.observe(ValueObservation.tracking { db in
                                                 (try AnnotationQueries.overrides(db), try AnnotationQueries.annotations(db).filter { $0.state == "ambiguous" })
                                             },
                                             onError: { print("overrides observation: \($0)") },
                                             onChange: { [weak self] in self?.overrides = $0.0; self?.ambiguous = $0.1 })
        observeUpcoming()
    }

    func set(today: LocalDay) {
        guard today != self.today else { return }
        self.today = today
        observeUpcoming()
    }

    private func observeUpcoming() {
        guard let store else { return }
        let today = self.today, horizon = self.horizon
        upcomingObservation = store.observe(ValueObservation.tracking { try TaskQueries.upcoming($0, today: today, horizon: horizon) },
                                            onError: { print("upcoming observation: \($0)") },
                                            onChange: { [weak self] in self?.upcoming = $0 })
    }

    func setEffortMinutes(_ minutes: Int?, for effort: Effort) {
        settings.setEffortMinutes(minutes, for: effort)
        sizes = settings.effortSizes
    }

    func classify(_ a: Appointment) -> (weight: BlockingWeight, reason: BlockingReason) { overrides.classify(a) }

    /// Free working minutes of a day; for today from `now` on.
    func freeMinutes(on day: LocalDay, now: Date, appointments: [Appointment]) -> Double {
        let from = day == LocalDay(date: now) ? now : day.interval().start
        return FreeTime.minutes(from: from, to: day.interval().end, busy: overrides.busy(appointments), hours: hours)
    }

    /// States for tasks, each on its own against the free time until its deadline.
    func evaluate(_ tasks: [TaskItem], now: Date, appointments: [Appointment]) -> [WorkOnItem] {
        Planning.evaluate(tasks, now: now, sizes: sizes, hours: hours, busy: overrides.busy(appointments))
    }

    /// The range "Work on" needs appointments for: today through the horizon.
    func horizonRange(today: LocalDay) -> DateInterval {
        DateInterval(start: today.interval().start, end: today.adding(days: horizon).interval().end)
    }
}

extension WorkOnState {
    var label: String {
        switch self {
        case .late: "late"
        case .tight: "tight"
        case .startToday: "start today"
        case .ok: "ok"
        case .noEstimate: "no estimate"
        }
    }
}

extension Effort {
    var label: String { rawValue }
}

func formatMinutes(_ m: Double) -> String {
    let total = Int(m.rounded())
    let h = total / 60, min = total % 60
    if h == 0 { return "\(min)m" }
    return min == 0 ? "\(h)h" : "\(h)h \(min)m"
}
