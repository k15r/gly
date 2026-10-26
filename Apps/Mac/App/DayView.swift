import SwiftUI
import WorkDashCore

/// The main screen (specs/day-view): one day with all visible appointments and the tasks for that day.
struct DayView: View {
    @Environment(AppModel.self) private var app
    @Environment(CalendarModel.self) private var calendars
    @Environment(TasksModel.self) private var tasks
    @Environment(Clock.self) private var clock
    @Binding var day: LocalDay
    @State private var editing: TaskEditorTarget?

    private var model: DayModel {
        DayModel(day: day, now: clock.now, appointments: calendars.appointments, calendars: calendars.calendars, tasks: tasks.dayTasks)
    }

    var body: some View {
        let model = self.model
        VStack(alignment: .leading, spacing: 0) {
            header(model)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    appointmentsSection(model)
                    tasksSection(model)
                }
                .padding()
            }
        }
        .sheet(item: $editing) { TaskEditor(target: $0) }
    }

    // MARK: Header

    private func header(_ model: DayModel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: day)).font(.title2.bold())
                if model.isToday { Text("Today").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            SourceIndicators()
            Button { day = day.adding(days: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous day (⌘←)")
            Button("Today") { day = clock.today }
                .disabled(model.isToday)
            Button { day = day.adding(days: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next day (⌘→)")
        }
        .padding()
    }

    static func title(for day: LocalDay) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM yyyy")
        return f.string(from: day.interval().start)
    }

    // MARK: Appointments

    @ViewBuilder
    private func appointmentsSection(_ model: DayModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Appointments").font(.headline)
            if !calendars.authorization.canRead {
                NoCalendarAccessView()
            } else if !model.hasAppointments {
                Text("No appointments").foregroundStyle(.secondary)
            } else {
                if !model.allDay.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.allDay) { AppointmentRow(entry: $0, allDay: true) }
                    }
                    .padding(.bottom, 4)
                }
                ForEach(model.timed) { AppointmentRow(entry: $0, allDay: false) }
            }
        }
    }

    // MARK: Tasks

    private func tasksSection(_ model: DayModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.isToday ? "Tasks due today" : "Tasks due this day").font(.headline)
                Spacer()
                Button { editing = .new(due: Due(day: day.description)) } label: { Label("New Task", systemImage: "plus") }
                    .disabled(!app.canWrite)
            }
            if model.tasks.isEmpty {
                Text("No tasks").foregroundStyle(.secondary)
            } else {
                ForEach(model.tasks) { dayTask in
                    TaskRow(task: dayTask.task, overdue: dayTask.isOverdue,
                            onEdit: { editing = .edit(dayTask.task.id) })
                }
            }
        }
    }

    func newTask() { editing = .new(due: Due(day: day.description)) }
}

/// One appointment line: time, color, title, calendar; cancelled struck through; past dimmed; current highlighted.
struct AppointmentRow: View {
    let entry: DayAppointment
    let allDay: Bool

    var body: some View {
        let a = entry.appointment
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: entry.calendar?.colorHex ?? "#888888")).frame(width: 4)
            if !allDay {
                Text(timeRange).font(.system(.body, design: .monospaced)).frame(width: 120, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(a.title).strikethrough(a.isCancelled).fontWeight(entry.state == .current ? .semibold : .regular)
                    if a.isCancelled { Text("Cancelled").font(.caption).padding(.horizontal, 4).background(.red.opacity(0.15)).clipShape(Capsule()) }
                    if entry.state == .current { Text("Now").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 5).background(.blue).clipShape(Capsule()) }
                }
                Text([entry.calendar?.title, a.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(6)
        .background(entry.state == .current ? Color.blue.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(entry.state == .past ? 0.5 : 1)
        .help(a.attendees.isEmpty ? a.title : "\(a.title)\n\(a.attendees.joined(separator: ", "))")
    }

    private var timeRange: String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        let start = entry.startsBeforeDay ? "…" : f.string(from: entry.appointment.start)
        let end = entry.endsAfterDay ? "…" : f.string(from: entry.appointment.end)
        return "\(start)–\(end)"
    }
}

/// Per-account "last change seen" (specs/calendar-sources "Calendar refresh indicator"); approximate by design.
struct SourceIndicators: View {
    @Environment(CalendarModel.self) private var calendars
    @Environment(Clock.self) private var clock

    var body: some View {
        HStack(spacing: 10) {
            ForEach(calendars.sourceStatuses, id: \.sourceID) { s in
                Text("\(s.sourceTitle): \(age(s.lastChangeSeen))")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Last change WorkDash saw from this account. EventKit doesn't report sync times, so this shows changes seen, not sync attempts.")
            }
            Button { calendars.refreshSources() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Ask the calendar accounts to refresh")
        }
    }

    private func age(_ date: Date?) -> String {
        guard let date else { return "no changes since launch" }
        let minutes = Int(clock.now.timeIntervalSince(date) / 60)
        return minutes < 1 ? "just now" : "\(minutes) min ago"
    }
}
