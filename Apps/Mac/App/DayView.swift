import SwiftUI
import WorkDashCore

/// The main screen (specs/day-view): one day with all visible appointments and the tasks for that day.
struct DayView: View {
    @Environment(AppModel.self) private var app
    @Environment(CalendarModel.self) private var calendars
    @Environment(TasksModel.self) private var tasks
    @Environment(Clock.self) private var clock
    @Environment(Navigation.self) private var nav
    @Environment(PlanningModel.self) private var planning
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
                    AmbiguityBanner(day: day)
                    appointmentsSection(model)
                    tasksSection(model)
                    if model.isToday { workOnSection() }
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
            CapacityIndicator(day: day)
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
                let states = model.isToday ? Dictionary(uniqueKeysWithValues: planning.evaluate(model.tasks.map(\.task), now: clock.now,
                    appointments: calendars.appointments(in: planning.horizonRange(today: clock.today))).map { ($0.task.id, $0.state) }) : [:]
                ForEach(model.tasks) { dayTask in
                    TaskRow(task: dayTask.task, overdue: dayTask.isOverdue,
                            onEdit: { nav.go(.task(dayTask.task.id)) }, state: states[dayTask.task.id])
                }
            }
        }
    }

    /// Open tasks due within the horizon, sorted by urgency (specs/daily-planning "Work on list").
    private func workOnSection() -> some View {
        @Bindable var planning = planning
        let items = planning.evaluate(planning.upcoming, now: clock.now,
                                      appointments: calendars.appointments(in: planning.horizonRange(today: clock.today)))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Work on").font(.headline)
                Spacer()
                Picker("", selection: $planning.horizon) {
                    ForEach([3, 5, 7, 14], id: \.self) { Text("next \($0) days").tag($0) }
                }
                .fixedSize().help("How far ahead to look (also in Settings → Planning)")
            }
            if items.isEmpty {
                Text("Nothing due in the next \(planning.horizon) days").foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    TaskRow(task: item.task, onEdit: { nav.go(.task(item.task.id)) }, state: item.state)
                        .help(item.effortMinutes.map { "Needs ~\(formatMinutes(Double($0))), free until due: \(formatMinutes(item.freeMinutes))" }
                              ?? "No estimate – set an effort to see whether it fits")
                }
            }
        }
    }

    func newTask() { editing = .new(due: Due(day: day.description)) }
}

/// Today's (or the displayed day's) free time against the working hours (specs/daily-planning "Capacity indicator").
struct CapacityIndicator: View {
    @Environment(PlanningModel.self) private var planning
    @Environment(CalendarModel.self) private var calendars
    @Environment(Clock.self) private var clock
    let day: LocalDay

    var body: some View {
        let free = planning.freeMinutes(on: day, now: clock.now, appointments: calendars.appointments)
        let total = Double(max(1, planning.hours.minutesPerDay))
        HStack(spacing: 6) {
            Text("free \(formatMinutes(free))").font(.caption.bold()).monospacedDigit()
            ProgressView(value: min(1, free / total)).frame(width: 70)
        }
        .help(day == clock.today ? "Free working time left today" : "Free working time on this day")
    }
}

/// Annotations whose appointment couldn't be identified uniquely after a calendar change (design Q4).
struct AmbiguityBanner: View {
    @Environment(PlanningModel.self) private var planning
    @Environment(CalendarModel.self) private var calendars
    @Environment(AppModel.self) private var app
    let day: LocalDay

    var body: some View {
        let mine = planning.ambiguous.filter { LocalDay(date: $0.start) == day }
        ForEach(mine) { a in
            let candidates = calendars.appointments.filter {
                $0.calendarID == a.calendarID && TagName.key(for: $0.title) == TagName.key(for: a.title)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("Which appointment does “\(a.title)” (\(a.blocking?.rawValue ?? "override")) belong to?", systemImage: "questionmark.circle")
                    .fontWeight(.medium)
                HStack {
                    ForEach(candidates) { c in
                        Button(c.start.formatted(date: .omitted, time: .shortened) + "–" + c.end.formatted(date: .omitted, time: .shortened)) {
                            Task { await app.send(.resolveAnnotation(id: a.id, to: AppointmentSnapshot(c))) }
                        }
                    }
                }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// One appointment line: time, color, title, calendar; cancelled struck through; past dimmed; current highlighted.
struct AppointmentRow: View {
    @Environment(PlanningModel.self) private var planning
    @Environment(AppModel.self) private var app
    let entry: DayAppointment
    let allDay: Bool
    @State private var showingDetails = false
    /// Click position within the row, so the popover points at the cursor.
    @State private var clickPoint: UnitPoint = .center
    @State private var size: CGSize = .zero

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
            blockingMenu
        }
        .padding(6)
        .background(entry.state == .current ? Color.blue.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(entry.state == .past ? 0.5 : 1)
        .contentShape(Rectangle())
        .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { size = g.size } })
        .onTapGesture(coordinateSpace: .local) { p in
            // A click that just dismissed an open popover only closes it (the popover closes on mouse-down, the tap fires on mouse-up).
            guard Date().timeIntervalSince(AppointmentPopover.lastClosed) > 0.5 else { return }
            clickPoint = size.width > 0 && size.height > 0 ? UnitPoint(x: p.x / size.width, y: p.y / size.height) : .center
            showingDetails = true
        }
        .popover(isPresented: $showingDetails, attachmentAnchor: .point(clickPoint), arrowEdge: .bottom) { AppointmentDetails(entry: entry) }
        .onChange(of: showingDetails) { _, open in if !open { AppointmentPopover.lastClosed = Date() } }
    }

    /// How this appointment counts for free time, and the override menu (specs/appointment-annotations "Blocking override menu").
    private var blockingMenu: some View {
        let (weight, reason) = planning.classify(entry.appointment)
        let symbol: String = switch weight { case .blocks: "circle.fill"; case .maybe: "circle.lefthalf.filled"; case .free: "circle" }
        let reasonText: String = switch reason { case .automatic: "automatic"; case .occurrenceOverride: "set for this occurrence"; case .seriesOverride: "set for the series" }
        return Menu {
            Section("This occurrence") { options(.occurrence) }
            if entry.appointment.isRecurring { Section("Whole series") { options(.series) } }
        } label: {
            Image(systemName: symbol).foregroundStyle(reason == .automatic ? Color.secondary : Color.accentColor)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Counts as \(weight == .maybe ? "half (maybe)" : weight.rawValue) for free time – \(reasonText)")
    }

    @ViewBuilder
    private func options(_ scope: BlockingScope) -> some View {
        Button("Automatic") { set(scope, nil) }
        Button("Blocks") { set(scope, .blocks) }
        Button("Optional (counts half)") { set(scope, .optional) }
        Button("Ignore") { set(scope, .ignore) }
    }

    private func set(_ scope: BlockingScope, _ value: BlockingOverride?) {
        Task { await app.send(.setBlocking(AppointmentSnapshot(entry.appointment), scope: scope, value: value)) }
    }

    private var timeRange: String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        let start = entry.startsBeforeDay ? "…" : f.string(from: entry.appointment.start)
        let end = entry.endsAfterDay ? "…" : f.string(from: entry.appointment.end)
        return "\(start)–\(end)"
    }
}

/// When an appointment popover was last closed, shared by all rows.
@MainActor
enum AppointmentPopover {
    static var lastClosed = Date.distantPast
}

/// Read-only appointment details (specs/calendar-sources "Appointment details are not editable").
struct AppointmentDetails: View {
    let entry: DayAppointment

    var body: some View {
        let a = entry.appointment
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(Color(hex: entry.calendar?.colorHex ?? "#888888")).frame(width: 10, height: 10)
                Text(a.title).font(.headline).strikethrough(a.isCancelled)
                if a.isCancelled { Text("Cancelled").font(.caption).padding(.horizontal, 4).background(.red.opacity(0.15)).clipShape(Capsule()) }
            }
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 6) {
                row("When", Self.when(a))
                if let c = entry.calendar { row("Calendar", "\(c.title) · \(c.sourceTitle)") }
                if let l = a.location, !l.isEmpty { row("Location", l) }
                if let o = a.organizer, !o.isEmpty { row("Organizer", o) }
                if !a.attendees.isEmpty { row("Attendees", a.attendees.joined(separator: "\n")) }
            }
        }
        .textSelection(.enabled)
        .padding()
        .frame(minWidth: 280, maxWidth: 420, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func when(_ a: Appointment) -> String {
        let f = DateIntervalFormatter()
        f.dateStyle = .medium
        f.timeStyle = a.isAllDay ? .none : .short
        // All-day events end at the next midnight; show the last day instead.
        let end = a.isAllDay ? max(a.start, a.end.addingTimeInterval(-1)) : a.end
        return f.string(from: a.start, to: end)
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
