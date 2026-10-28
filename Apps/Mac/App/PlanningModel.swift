import Foundation
import GRDB
import Observation
import GlyCore

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
    /// Tasks still snoozed on the planned day (future-day-planning F5).
    private(set) var snoozed: [TaskItem] = []
    /// Minutes ticked off as "done for today" today, per task (task-progress P4).
    private(set) var partsToday: [String: Int] = [:]

    @ObservationIgnored private var store: ReadOnlyStore?
    /// The day planned for: the displayed day if it is today or later (a forecast), else nothing to plan (F1, F2).
    @ObservationIgnored private var planDay: LocalDay? = LocalDay(date: Date())
    @ObservationIgnored private var overridesObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var upcomingObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var snoozedObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var partsObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var today = LocalDay(date: Date())

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
        observeParts()
    }

    private func observeParts() {
        guard let store else { return }
        let today = self.today
        partsObservation = store.observe(ValueObservation.tracking { try TaskQueries.partsRecorded($0, on: today) },
                                         onError: { print("parts observation: \($0)") },
                                         onChange: { [weak self] in self?.partsToday = $0 })
    }

    func set(day: LocalDay, today: LocalDay) {
        if today != self.today { self.today = today; observeParts() }
        let planDay = day >= today ? day : nil
        guard planDay != self.planDay else { return }
        self.planDay = planDay
        observeUpcoming()
    }

    private func observeUpcoming() {
        guard let store, let day = planDay else {
            upcomingObservation = nil; upcoming = []
            snoozedObservation = nil; snoozed = []
            return
        }
        snoozedObservation = store.observe(ValueObservation.tracking { try TaskQueries.snoozed($0, after: day) },
                                           onError: { print("snoozed observation: \($0)") },
                                           onChange: { [weak self] in self?.snoozed = $0 })
        let horizon = self.horizon
        upcomingObservation = store.observe(ValueObservation.tracking { try TaskQueries.upcoming($0, today: day, horizon: horizon) },
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

    /// Whether the task, back from a snooze on `day`, still fits before its due date; nil when there's nothing to judge (F4).
    func fits(_ task: TaskItem, returningOn day: LocalDay, calendars: CalendarModel) -> Bool? {
        guard task.effort != nil, let deadline = Planning.deadline(of: task) else { return nil }
        let start = day.interval().start
        let appointments = start < deadline ? calendars.appointments(in: DateInterval(start: start, end: deadline)) : []
        return Planning.fits(task, returningOn: day, sizes: sizes, hours: hours, busy: overrides.busy(appointments))
    }

    /// Today and Coming up, each task on its own against the free time until its deadline.
    func plan(_ tasks: [TaskItem], now: Date, appointments: [Appointment]) -> DayPlan {
        Planning.plan(tasks, now: now, sizes: sizes, hours: hours, busy: overrides.busy(appointments))
    }

    /// The range "Work on" needs appointments for: today through the horizon.
    func horizonRange(today: LocalDay) -> DateInterval {
        DateInterval(start: today.interval().start, end: today.adding(days: horizon).interval().end)
    }
}

import SwiftUI

/// A short planning note on a task row ("today ≥ 2h", "start by Wed", "can't fit").
struct PlanNote: Equatable {
    let text: String
    let color: Color
    let help: String
}

extension Effort {
    var label: String { rawValue }
}

/// Effort-style duration: working days when it's at least a day ("1d 2h"), otherwise hours and minutes.
func formatEffort(_ m: Double, dayLength: Int) -> String {
    let total = Int(m.rounded()), day = max(60, dayLength)
    guard total >= day else { return formatMinutes(m) }
    let d = total / day, rest = total % day
    return rest == 0 ? "\(d)d" : "\(d)d " + formatMinutes(Double(rest))
}

func formatMinutes(_ m: Double) -> String {
    let total = Int(m.rounded())
    let h = total / 60, min = total % 60
    if h == 0 { return "\(min)m" }
    return min == 0 ? "\(h)h" : "\(h)h \(min)m"
}
