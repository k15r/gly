// Spike 1 (foundation-spikes): EventKit appointment identity probe. Throwaway code.
//
// Usage:
//   eventkit-probe list     [--from YYYY-MM-DD] [--days N] [--calendar SUBSTR] [--title SUBSTR]
//   eventkit-probe snapshot --out FILE [same filters]
//   eventkit-probe diff     A.json B.json
//   eventkit-probe calendars

import EventKit
import Foundation

struct EventRecord: Codable, Equatable {
    var key: String                    // source/calendar + "/" + externalId + "@" + occurrenceDate (ISO)
    var stableKey: String?             // calendar + base externalId (RID stripped) + original start (finding F6)
    var externalId: String?
    var eventIdentifier: String?
    var occurrenceDate: String?
    var startDate: String
    var endDate: String
    var status: String
    var title: String
    var organizer: String?
    var calendar: String
    var source: String
    var hasRecurrence: Bool
    var isDetached: Bool
    var lastModified: String?
    var attendeeCount: Int
}

struct Snapshot: Codable {
    var takenAt: String
    var from: String
    var to: String
    var events: [EventRecord]
}

let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func statusName(_ s: EKEventStatus) -> String {
    switch s {
    case .none: return "none"
    case .confirmed: return "confirmed"
    case .tentative: return "tentative"
    case .canceled: return "canceled"
    @unknown default: return "unknown(\(s.rawValue))"
    }
}

// Finding F6: editing a single occurrence detaches it; its external ID gets "/RID=<seconds since 2001-01-01>"
// encoding the ORIGINAL start, while occurrenceDate follows the new start.
func stableKey(calendar: String, externalId: String?, occurrence: Date?) -> String {
    guard var ext = externalId else { return "\(calendar)/nil@nil" }
    var original = occurrence
    if let r = ext.range(of: "/RID=") {
        let rid = ext[r.upperBound...]
        if let secs = Double(rid) { original = Date(timeIntervalSinceReferenceDate: secs) }
        ext = String(ext[..<r.lowerBound])
    }
    return "\(calendar)/\(ext)@\(original.map { iso.string(from: $0) } ?? "nil")"
}

func record(_ e: EKEvent) -> EventRecord {
    let occ = e.occurrenceDate.map { iso.string(from: $0) }
    let ext = e.calendarItemExternalIdentifier
    let organizer = e.organizer.map { p -> String in
        let name = p.name ?? ""
        return name.isEmpty ? p.url.absoluteString : "\(name) <\(p.url.absoluteString)>"
    }
    return EventRecord(
        // Same externalId can live in several calendars (e.g. shared iCloud calendars), so the calendar is part of the key.
        key: "\(e.calendar.source.title)/\(e.calendar.title)/\(ext ?? "nil")@\(occ ?? "nil")",
        stableKey: stableKey(calendar: "\(e.calendar.source.title)/\(e.calendar.title)", externalId: ext, occurrence: e.occurrenceDate),
        externalId: ext,
        eventIdentifier: e.eventIdentifier,
        occurrenceDate: occ,
        startDate: iso.string(from: e.startDate),
        endDate: iso.string(from: e.endDate),
        status: statusName(e.status),
        title: e.title ?? "",
        organizer: organizer,
        calendar: e.calendar.title,
        source: e.calendar.source.title,
        hasRecurrence: e.hasRecurrenceRules,
        isDetached: e.isDetached,
        lastModified: e.lastModifiedDate.map { iso.string(from: $0) },
        attendeeCount: e.attendees?.count ?? 0
    )
}

func requestAccess(_ store: EKEventStore) {
    let status = EKEventStore.authorizationStatus(for: .event)
    FileHandle.standardError.write("authorization status: \(status.rawValue) (3=fullAccess, 0=notDetermined, 2=denied)\n".data(using: .utf8)!)
    if status == .fullAccess { return }
    var done = false
    var granted = false
    var error: Error?
    store.requestFullAccessToEvents { g, e in
        granted = g
        error = e
        done = true
    }
    // Keep the main run loop alive: the TCC prompt and callback may need it.
    while !done {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    if !granted {
        fail("Calendar access not granted (\(error?.localizedDescription ?? "denied")). "
            + "Allow it under System Settings > Privacy & Security > Calendars for your terminal app.")
    }
}

struct Options {
    var from = Calendar.current.startOfDay(for: Date())
    var days = 14
    var calendar: String?
    var title: String?
    var out: String?
}

func parseOptions(_ args: ArraySlice<String>) -> Options {
    var o = Options()
    var it = args.makeIterator()
    while let a = it.next() {
        switch a {
        case "--from":
            guard let v = it.next() else { fail("--from needs a value") }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            guard let d = f.date(from: v) else { fail("bad date \(v)") }
            o.from = d
        case "--days":
            guard let v = it.next(), let n = Int(v) else { fail("--days needs a number") }
            o.days = n
        case "--calendar":
            o.calendar = it.next()
        case "--title":
            o.title = it.next()
        case "--out":
            o.out = it.next()
        default:
            fail("unknown option \(a)")
        }
    }
    return o
}

func fetch(_ store: EKEventStore, _ o: Options) -> (Date, Date, [EventRecord]) {
    let to = Calendar.current.date(byAdding: .day, value: o.days, to: o.from)!
    var calendars = store.calendars(for: .event)
    if let c = o.calendar {
        calendars = calendars.filter {
            $0.title.localizedCaseInsensitiveContains(c) || $0.source.title.localizedCaseInsensitiveContains(c)
        }
    }
    // EventKit limits predicate ranges to 4 years; fine for this probe.
    let pred = store.predicateForEvents(withStart: o.from, end: to, calendars: calendars)
    var events = store.events(matching: pred).map(record)
    if let t = o.title {
        events = events.filter { $0.title.localizedCaseInsensitiveContains(t) }
    }
    events.sort { ($0.startDate, $0.key) < ($1.startDate, $1.key) }
    return (o.from, to, events)
}

func printTable(_ events: [EventRecord]) {
    for e in events {
        print("""
        \(e.startDate)  [\(e.status)] \(e.title)
            calendar: \(e.calendar) (\(e.source))  recurring: \(e.hasRecurrence)  detached: \(e.isDetached)  attendees: \(e.attendeeCount)
            externalId: \(e.externalId ?? "nil")
            occurrence: \(e.occurrenceDate ?? "nil")
            eventId:    \(e.eventIdentifier ?? "nil")
            organizer:  \(e.organizer ?? "-")
        """)
    }
    print("\n\(events.count) events")
}

func load(_ path: String) -> Snapshot {
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    do { return try JSONDecoder().decode(Snapshot.self, from: data) } catch { fail("bad snapshot \(path): \(error)") }
}

func diff(_ a: Snapshot, _ b: Snapshot) -> Int {
    // Diff by the normalized key (F6); fall back to the raw key for old snapshots.
    let ma = Dictionary(a.events.map { ($0.stableKey ?? $0.key, $0) }, uniquingKeysWith: { x, _ in x })
    let mb = Dictionary(b.events.map { ($0.stableKey ?? $0.key, $0) }, uniquingKeysWith: { x, _ in x })
    var differences = 0
    let dupA = a.events.count - ma.count, dupB = b.events.count - mb.count
    if dupA > 0 || dupB > 0 {
        print("WARNING duplicate keys: A=\(dupA) B=\(dupB)")
        differences += dupA + dupB
    }
    for k in ma.keys.sorted() where mb[k] == nil {
        print("- removed  \(k)  \(ma[k]!.title)  \(ma[k]!.startDate)")
        differences += 1
    }
    for k in mb.keys.sorted() where ma[k] == nil {
        print("+ added    \(k)  \(mb[k]!.title)  \(mb[k]!.startDate)")
        differences += 1
    }
    for k in ma.keys.sorted() {
        guard let x = ma[k], let y = mb[k], x != y else { continue }
        var fields: [String] = []
        let mx = Mirror(reflecting: x), my = Mirror(reflecting: y)
        for (cx, cy) in zip(mx.children, my.children) where "\(cx.value)" != "\(cy.value)" {
            fields.append("\(cx.label ?? "?"): \(cx.value) -> \(cy.value)")
        }
        print("~ changed  \(k)  \(x.title)")
        fields.forEach { print("      \($0)") }
        differences += 1
    }
    print("\n\(differences) differences (A: \(a.events.count) events, B: \(b.events.count) events)")
    return differences
}

let args = CommandLine.arguments.dropFirst()
guard let cmd = args.first else {
    fail("usage: eventkit-probe list|snapshot|diff|calendars ...")
}

switch cmd {
case "diff":
    let rest = Array(args.dropFirst())
    guard rest.count == 2 else { fail("usage: eventkit-probe diff A.json B.json") }
    exit(diff(load(rest[0]), load(rest[1])) == 0 ? 0 : 2)

case "calendars":
    let store = EKEventStore()
    requestAccess(store)
    for c in store.calendars(for: .event).sorted(by: { ($0.source.title, $0.title) < ($1.source.title, $1.title) }) {
        print("\(c.source.title) / \(c.title)  [\(c.type.rawValue)]  id: \(c.calendarIdentifier)")
    }

case "list", "snapshot":
    let o = parseOptions(args.dropFirst())
    let store = EKEventStore()
    requestAccess(store)
    let (from, to, events) = fetch(store, o)
    if cmd == "list" {
        printTable(events)
    } else {
        guard let out = o.out else { fail("snapshot needs --out FILE") }
        let snap = Snapshot(takenAt: iso.string(from: Date()), from: iso.string(from: from), to: iso.string(from: to), events: events)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try! enc.encode(snap).write(to: URL(fileURLWithPath: out))
        print("wrote \(events.count) events to \(out)")
    }

default:
    fail("unknown command \(cmd)")
}
