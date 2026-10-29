import SwiftUI
import GlyCore

struct MeetingPageData: Equatable {
    var itemID: String?
    var body: String
    var item: MeetingNotesItem?
    var backlinks: [Backlink]
    /// For notes opened by id: the series rule, to find a live occurrence for the header.
    var rule: SeriesRule?
}

/// A meeting's notes page (specs/meeting-pages, design N7): meeting facts and description, then the notes
/// (one ever-growing document per series with dated sections, or one per one-off meeting), tags and backlinks.
struct MeetingPageView: View {
    @Environment(AppModel.self) private var app
    @Environment(WikiModel.self) private var wiki
    @Environment(Navigation.self) private var nav
    @Environment(CalendarModel.self) private var calendars
    @Environment(Clock.self) private var clock
    let ref: MeetingRef

    @State private var live = Live<MeetingPageData>()
    @State private var appointment: Appointment?
    @State private var tags: [String] = []
    @State private var pendingTag = ""

    var body: some View {
        Group {
            if let data = live.value, appointment != nil || data.item != nil {
                content(data)
            } else if live.loaded {
                ContentUnavailableView("Meeting not found", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("Its notes may have been deleted."))
            } else {
                ProgressView()
            }
        }
        .task(id: ref) {
            switch ref {
            case .appointment(let a):
                appointment = a
                live.observe(wiki.store) { db in
                    let doc = try MeetingNotes.document(for: a, db: db)
                    let item = try doc.itemID.flatMap { try MeetingNotes.item(db, id: $0) }
                    return MeetingPageData(itemID: doc.itemID, body: doc.body, item: item,
                                           backlinks: try doc.itemID.map { try LinkQueries.backlinks(db, to: $0) } ?? [])
                }
            case .notes(let id):
                appointment = nil
                live.observe(wiki.store) { db in
                    let item = try MeetingNotes.item(db, id: id)
                    let rule = try item?.seriesRuleID.flatMap { rid in try AnnotationQueries.seriesRules(db).first { $0.id == rid } }
                    return MeetingPageData(itemID: id, body: item?.body ?? "", item: item, backlinks: try LinkQueries.backlinks(db, to: id), rule: rule)
                }
            }
        }
        .onChange(of: live.value) { _, data in
            guard let data else { return }
            tags = data.item?.tags ?? []
            if appointment == nil, case .notes = ref { appointment = liveOccurrence(for: data) }
        }
    }

    // MARK: Content

    private func content(_ data: MeetingPageData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(data).padding([.horizontal, .top])
            TagField(tags: $tags, input: $pendingTag)
                .padding(.horizontal).padding(.top, 6)
                .onChange(of: tags) { _, new in
                    guard new != (data.item?.tags ?? []) else { return }
                    save(data, body: nil, tags: new, session: nil)
                }
            Divider().padding(.top, 8)
            // One mode: the live-preview editor; opened from an appointment, the caret starts in that meeting's section.
            let (text, caret) = editorText(data)
            GlyMarkdownEditor(text: text, onCommit: { new, session in save(data, body: new, tags: nil, session: session) },
                             initialCaret: caret)
                .id(ref)
                .frame(maxHeight: .infinity)
            Divider()
            BacklinksView(backlinks: data.backlinks).padding().frame(maxHeight: 160, alignment: .top)
        }
    }

    private func header(_ data: MeetingPageData) -> some View {
        let a = appointment
        let title = a?.title ?? data.item?.title ?? "Meeting"
        let recurring = a?.isRecurring ?? (data.item?.seriesRuleID != nil)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "calendar").font(.title2).foregroundStyle(.secondary)
                Text(title).font(.title.bold()).lineLimit(2)
                if recurring { Text("series notes").font(.caption).foregroundStyle(.secondary).help("One document for every meeting of this series") }
                stateBadge(data)
                Spacer()
                Menu {
                    Button("Delete Notes", role: .destructive) { deleteNotes(data) }.disabled(data.itemID == nil || data.body.isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().disabled(!app.canWrite)
            }
            Text(factsLine(a, data)).font(.callout).foregroundStyle(.secondary)
            if let a {
                if !a.attendees.isEmpty {
                    DisclosureGroup("\(a.attendees.count) attendee\(a.attendees.count == 1 ? "" : "s")") {
                        Text(a.attendees.joined(separator: ", ")).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                }
                let d = MeetingDescription.parse(notes: a.notes, location: a.location, url: a.url)
                if !d.agenda.isEmpty || d.dialIn != nil {
                    DisclosureGroup("Description") {
                        VStack(alignment: .leading, spacing: 6) {
                            if !d.agenda.isEmpty { Text(AppointmentDetails.linked(d.agenda)).fixedSize(horizontal: false, vertical: true) }
                            if let dial = d.dialIn {
                                DisclosureGroup("\(d.service ?? "Meeting") details") {
                                    Text(AppointmentDetails.linked(dial)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.caption)
                            }
                        }
                        .textSelection(.enabled)
                    }
                    .font(.callout)
                }
                if let join = d.joinURL {
                    Button { NSWorkspace.shared.open(join) } label: { Label("Join \(d.service ?? "")", systemImage: "video") }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder private func stateBadge(_ data: MeetingPageData) -> some View {
        switch data.item?.state {
        case "cancelled": badge("Cancelled", .red)
        case "gone": badge("No longer in the calendar", .orange)
        case "ambiguous": badge("Moved?", .orange)
        default: EmptyView()
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption).padding(.horizontal, 5).padding(.vertical, 1).background(color.opacity(0.15)).clipShape(Capsule())
    }

    private func factsLine(_ a: Appointment?, _ data: MeetingPageData) -> String {
        let start = a?.start ?? data.item?.start, end = a?.end ?? data.item?.end
        var parts: [String] = []
        if let start {
            let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
            let times = end.map { "\(start.formatted(date: .omitted, time: .shortened))–\($0.formatted(date: .omitted, time: .shortened))" }
            parts.append([day, times].compactMap { $0 }.joined(separator: ", "))
        }
        if let a {
            if let cal = calendars.calendars.first(where: { $0.id == a.calendarID }) { parts.append(cal.title) }
            if let l = a.location, !l.isEmpty { parts.append(l) }
            if let o = a.organizer, !o.isEmpty { parts.append(o) }
        } else if let o = data.item?.organizer, !o.isEmpty {
            parts.append(o)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Notes

    /// The text the editor starts with and where the caret goes: for a recurring meeting opened from one of its
    /// meetings, that meeting's section; a missing section is shown with its heading but only stored once typed into
    /// (the editor commits changes only).
    private func editorText(_ data: MeetingPageData) -> (String, Int?) {
        guard case .appointment(let a) = ref else { return (data.body, nil) }
        guard a.isRecurring else { return (data.body, (data.body as NSString).length) }
        let today = clock.today, day = LocalDay(date: a.start)
        if let s = NotesSections.section(for: day, in: data.body, today: today) { return (data.body, s.contentStart) }
        let text = NotesSections.insert("", for: day, into: data.body, today: today)
        return (text, NotesSections.section(for: day, in: text, today: today)?.contentStart)
    }

    private func save(_ data: MeetingPageData, body: String?, tags: [String]?, session: String?) {
        if let id = data.itemID {
            send(.updateMeetingNotes(id: id, body: body, tags: tags, session: session))
        } else if case .appointment(let a) = ref {
            send(.saveMeetingNotes(MeetingTarget(a), body: body ?? "", tags: tags, session: session))
        }
    }

    private func deleteNotes(_ data: MeetingPageData) {
        guard let id = data.itemID else { return }
        Task {
            guard case .ok = await app.send(.deleteMeetingNotes(id: id)) else { return }
            if case .notes = ref { nav.back() }
        }
    }

    private func send(_ command: Command) { Task { await app.send(command) } }

    /// For notes opened by id: the live meeting, for the header and description. An occurrence by its key around its
    /// last known time; a series' next meeting (else its most recent) within 30 days.
    private func liveOccurrence(for data: MeetingPageData) -> Appointment? {
        guard let item = data.item else { return nil }
        if let key = item.occurrenceKey, let start = item.start {
            return calendars.appointments(in: DateInterval(start: start.addingTimeInterval(-2 * 86400), end: start.addingTimeInterval(2 * 86400)))
                .first { $0.identity.occurrenceKey == key }
        }
        guard let rule = data.rule else { return nil }
        let now = Date()
        let matches = calendars.appointments(in: DateInterval(start: now.addingTimeInterval(-30 * 86400), end: now.addingTimeInterval(30 * 86400)))
            .filter { rule.matches($0) }.sorted { $0.start < $1.start }
        return matches.first { $0.end >= now } ?? matches.last
    }
}
