import Foundation

/// An appointment as shown in the day view.
public struct DayAppointment: Identifiable, Equatable {
    public enum TimeState: Equatable { case past, current, upcoming, notToday }
    public var id: String { appointment.id }
    public let appointment: Appointment
    public let calendar: CalendarInfo?
    public let state: TimeState
    /// Started before the displayed day / ends after it (spans midnight).
    public let startsBeforeDay: Bool
    public let endsAfterDay: Bool
}

/// Everything the day view shows, computed from plain inputs (design L8). No UI types.
public struct DayModel: Equatable {
    public let day: LocalDay
    public let isToday: Bool
    public let allDay: [DayAppointment]
    public let timed: [DayAppointment]
    public let tasks: [DayTask]

    public init(day: LocalDay, now: Date, calendar: Calendar = .current, appointments: [Appointment],
                calendars: [CalendarInfo], tasks: [DayTask]) {
        self.day = day
        let interval = day.interval(in: calendar)
        isToday = interval.contains(now)
        let calendarsByID = Dictionary(calendars.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Keep only appointments overlapping the day (sources may return a wider range); overlaps are all kept.
        let onDay = appointments.filter { $0.start < interval.end && $0.end > interval.start }
            .sorted { ($0.start, $0.end, $0.title) < ($1.start, $1.end, $1.title) }
        let isToday = self.isToday
        func entry(_ a: Appointment) -> DayAppointment {
            let state: DayAppointment.TimeState
            if !isToday || a.isAllDay { state = .notToday }
            else if a.end <= now { state = .past }
            else if a.start <= now { state = .current }
            else { state = .upcoming }
            return DayAppointment(appointment: a, calendar: calendarsByID[a.calendarID], state: state,
                                  startsBeforeDay: a.start < interval.start, endsAfterDay: a.end > interval.end)
        }
        allDay = onDay.filter(\.isAllDay).map(entry)
        timed = onDay.filter { !$0.isAllDay }.map(entry)
        self.tasks = tasks
    }

    public var hasAppointments: Bool { !allDay.isEmpty || !timed.isEmpty }
}
