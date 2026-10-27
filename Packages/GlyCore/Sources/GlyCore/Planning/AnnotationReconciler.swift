import Foundation
import GRDB

/// Runs the annotation matcher against the calendar (agent side, design Q4): after calendar changes,
/// at start and at midnight. Writes as the system writer through `CommandHandler`.
public final class AnnotationReconciler {
    let handler: CommandHandler
    let calendar: EventSource
    let writerName: String
    let now: () -> Date
    private var midnightTimer: Timer?

    public init(writer: DatabaseWriter, calendar: EventSource, writerName: String, now: @escaping () -> Date = Date.init) {
        self.handler = CommandHandler(writer: writer)
        self.calendar = calendar
        self.writerName = writerName
        self.now = now
    }

    /// The window that is matched: from 7 days ago to 60 days ahead.
    public func window(calendar cal: Calendar = .current) -> DateInterval {
        let today = LocalDay(date: now(), calendar: cal)
        return DateInterval(start: today.adding(days: -7, calendar: cal).interval(in: cal).start,
                            end: today.adding(days: 60, calendar: cal).interval(in: cal).end)
    }

    /// One reconciliation pass. Uses all calendars (not only visible ones), so hiding a calendar never makes annotations "gone".
    @discardableResult
    public func run() -> CommandResult? {
        guard calendar.authorization.canRead else { return nil }
        let w = window()
        let ids = Set(calendar.calendars().map(\.id))
        let observed = calendar.appointments(overlapping: w, calendarIDs: ids).map(ObservedAppointment.init)
        return handler.perform(.reconcileAnnotations(from: w.start, to: w.end, appointments: observed), writer: writerName)
    }

    /// Hooks calendar changes (already debounced by the source) and a midnight run, then runs once.
    public func start() {
        let previous = calendar.onChange
        calendar.onChange = { [weak self] in previous?(); self?.run() }
        scheduleMidnight()
        run()
    }

    private func scheduleMidnight() {
        let next = LocalDay(date: now()).adding(days: 1).interval().start.addingTimeInterval(60)
        midnightTimer?.invalidate()
        midnightTimer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in self?.run(); self?.scheduleMidnight() }
        RunLoop.main.add(midnightTimer!, forMode: .common)
    }
}
