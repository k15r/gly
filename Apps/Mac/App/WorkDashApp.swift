import AppKit
import SwiftUI
import WorkDashCore

@main
struct WorkDashApp: App {
    @State private var app = AppModel()
    @State private var calendars = CalendarModel()
    @State private var tasks = TasksModel()
    @State private var clock = Clock()
    @State private var nav = Navigation()

    var body: some Scene {
        WindowGroup("WorkDash") {
            ContentView()
                .environment(app).environment(calendars).environment(tasks).environment(clock).environment(nav)
                .frame(minWidth: 880, minHeight: 580)
                .task { await startUp() }
                .onChange(of: app.store === nil) { tasks.attach(app.store, writer: app.writer) }
                .onChange(of: nav.day) { syncDay() }
                .onChange(of: clock.today) { syncDay() }
        }
        .commands {
            // Store undo/redo via the agent; while a text field is focused, the text's own undo applies (design L6).
            CommandGroup(replacing: .undoRedo) {
                Button(tasks.undoLabel.map { "Undo \($0)" } ?? "Undo") { undoRedo(store: .undo, text: Selector(("undo:"))) }
                    .keyboardShortcut("z")
                Button(tasks.redoLabel.map { "Redo \($0)" } ?? "Redo") { undoRedo(store: .redo, text: Selector(("redo:"))) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            // Replaces File → New Window (single-window app), which would otherwise own ⌘N.
            CommandGroup(replacing: .newItem) {
                Button("New Task") { nav.requestNewTask() }.keyboardShortcut("n").disabled(!app.canWrite)
            }
            CommandMenu("Go") {
                Button("Previous Day") { nav.day = nav.day.adding(days: -1); nav.section = .day }.keyboardShortcut(.leftArrow)
                Button("Next Day") { nav.day = nav.day.adding(days: 1); nav.section = .day }.keyboardShortcut(.rightArrow)
                Button("Today") { nav.day = clock.today; nav.section = .day }.keyboardShortcut("t")
                Divider()
                Button("Tasks") { nav.section = .tasks }.keyboardShortcut("2")
                Button("Day") { nav.section = .day }.keyboardShortcut("1")
            }
            CommandMenu("Developer") {
                Button("Re-check Agent") { Task { await app.refreshAgentState() } }
                Button("Unregister Agent") { Task { await app.unregisterAgent() } }
            }
        }
    }

    private func startUp() async {
        clock.onDayChange = { newDay in
            // Midnight: persist snooze transitions and advance "today" if it was shown (design L8).
            Task { await app.send(.reconcileSnoozes(today: newDay.description), asSystem: true) }
            if nav.day == newDay.adding(days: -1) { nav.day = newDay }
        }
        await app.start()
        tasks.attach(app.store, writer: app.writer)
        if app.canWrite { await app.send(.reconcileSnoozes(today: clock.today.description), asSystem: true) }
        await calendars.start()
        syncDay()
    }

    private func syncDay() {
        tasks.set(day: nav.day, today: clock.today)
        calendars.show(day: nav.day)
    }

    private func undoRedo(store command: Command, text selector: Selector) {
        if NSApp.keyWindow?.firstResponder is NSText {
            NSApp.sendAction(selector, to: nil, from: nil)
        } else {
            Task { await app.undoRedo(command) }
        }
    }
}

/// Navigation state shared by the sidebar, the menu commands and the views.
@MainActor
@Observable
final class Navigation {
    enum Section: Hashable { case day, tasks, calendars }
    var section: Section = .day
    var day = LocalDay(date: Date())
    /// Incremented to ask the visible view to open a new-task editor (⌘N).
    private(set) var newTaskRequest = 0
    func requestNewTask() { newTaskRequest += 1 }
}

/// Banner shown when writes aren't possible (design L2, "Risks": login item not approved).
struct AgentBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.agentState {
        case .ready, .unknown:
            EmptyView()
        case .requiresApproval:
            banner("Writing disabled: allow the WorkDash agent in System Settings → Login Items.")
        case .unavailable(let reason):
            banner("Writing disabled: WorkDash agent not reachable. \(reason)")
        }
    }

    private func banner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(text).lineLimit(2)
            Spacer()
            Button("Open Login Items") { app.openLoginItems() }
            Button("Retry") { Task { await app.refreshAgentState() } }
        }
        .padding(8)
        .background(.yellow.opacity(0.15))
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(TasksModel.self) private var tasks
    @Environment(Navigation.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        @Bindable var app = app
        VStack(spacing: 0) {
            AgentBanner()
            NavigationSplitView {
                List(selection: Binding(get: { nav.section }, set: { if let s = $0 { nav.section = s } })) {
                    Label("Day", systemImage: "calendar").tag(Navigation.Section.day)
                    Label("Tasks", systemImage: "checklist").tag(Navigation.Section.tasks)
                    Label("Calendars", systemImage: "calendar.badge.checkmark").tag(Navigation.Section.calendars)
                    Section("Tags") { TagTreeView() }
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            } detail: {
                switch nav.section {
                case .day: DayContainer()
                case .tasks: TaskListContainer()
                case .calendars: CalendarListView()
                }
            }
        }
        .overlay {
            if let notice = app.undoNotice { UndoNoticeView(notice: notice).transition(.opacity).allowsHitTesting(false) }
        }
        .animation(.easeOut(duration: 0.2), value: app.undoNotice)
        .alert("WorkDash", isPresented: Binding(get: { app.lastError != nil }, set: { if !$0 { app.lastError = nil } })) {
            Button("OK") { app.lastError = nil }
        } message: { Text(app.lastError ?? "") }
    }
}

/// Brief centered overlay after undo/redo: a rewind (or forward) arrow and what was reverted.
struct UndoNoticeView: View {
    let notice: UndoNotice

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: notice.redo ? "arrow.clockwise" : "arrow.counterclockwise")
                .font(.system(size: 44, weight: .medium))
            Text(notice.label).font(.callout).multilineTextAlignment(.center).lineLimit(3)
        }
        .foregroundStyle(notice.changed ? .primary : .secondary)
        .padding(20)
        .frame(minWidth: 160, maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
    }
}

/// Wires ⌘N to the day view's "new task for the displayed day".
struct DayContainer: View {
    @Environment(Navigation.self) private var nav
    @State private var editing: TaskEditorTarget?
    var body: some View {
        @Bindable var nav = nav
        DayView(day: $nav.day)
            .onChange(of: nav.newTaskRequest) { editing = .new(due: Due(day: nav.day.description)) }
            .sheet(item: $editing) { TaskEditor(target: $0) }
    }
}

struct TaskListContainer: View {
    @Environment(Navigation.self) private var nav
    @State private var editing: TaskEditorTarget?
    var body: some View {
        TaskListView()
            .onChange(of: nav.newTaskRequest) { editing = .new(due: nil) }
            .sheet(item: $editing) { TaskEditor(target: $0) }
    }
}

/// Tag hierarchy with open-task counts; selecting a tag filters the task list (specs/tags "Tag list").
struct TagTreeView: View {
    @Environment(TasksModel.self) private var tasks
    @Environment(Navigation.self) private var nav

    var body: some View {
        if tasks.tagTree.isEmpty {
            Text("No tags on open tasks").font(.caption).foregroundStyle(.secondary)
        } else {
            OutlineGroup(tasks.tagTree, children: \.childrenOrNil) { node in
                Button {
                    tasks.tagFilter = try? TagName(node.path)
                    nav.section = .tasks
                } label: {
                    HStack {
                        Text(node.segment).fontWeight(tasks.tagFilter?.key == TagName.key(for: node.path) ? .bold : .regular)
                        Spacer()
                        Text("\(node.openCount)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension TagNode {
    var childrenOrNil: [TagNode]? { children.isEmpty ? nil : children }
}
