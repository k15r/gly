import EventKit
import Foundation

/// Temporary probe for planning-day-view task 1.1: which attendance fields EventKit delivers per account type.
/// Writes only aggregated counts (no titles, names or ids) to the app container.
enum AttendanceProbe {
    static func run() -> String {
        let store = EKEventStore()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return "No calendar access." }
        let now = Date()
        let events = store.events(matching: store.predicateForEvents(withStart: now.addingTimeInterval(-14 * 86400),
                                                                      end: now.addingTimeInterval(14 * 86400), calendars: nil))
        var stats: [String: [String: Int]] = [:]
        func count(_ source: String, _ key: String) { stats[source, default: [:]][key, default: 0] += 1 }
        for e in events {
            let type: String
            switch e.calendar.source.sourceType {
            case .exchange: type = "exchange"
            case .calDAV: type = "caldav(icloud/other)"
            case .local: type = "local"
            case .subscribed: type = "subscribed"
            case .birthdays: type = "birthdays"
            case .mobileMe: type = "mobileme"
            @unknown default: type = "other"
            }
            count(type, "events")
            count(type, e.isAllDay ? "allDay" : "timed")
            let availability: String = switch e.availability {
            case .notSupported: "notSupported"
            case .busy: "busy"
            case .free: "free"
            case .tentative: "tentative"
            case .unavailable: "unavailable"
            @unknown default: "unknown"
            }
            count(type, "availability.\(availability)")
            let attendees = e.attendees ?? []
            count(type, attendees.isEmpty ? "attendees.none" : "attendees.some")
            if let me = attendees.first(where: \.isCurrentUser) {
                let status: String = switch me.participantStatus {
                case .accepted: "accepted"
                case .declined: "declined"
                case .tentative: "tentative"
                case .pending: "pending"
                case .unknown: "unknown"
                case .delegated: "delegated"
                case .completed: "completed"
                case .inProcess: "inProcess"
                @unknown default: "other"
                }
                count(type, "me.\(status)")
            } else if !attendees.isEmpty {
                count(type, "me.notInAttendees")
            }
            if e.organizer?.isCurrentUser == true { count(type, "organizer.me") }
            if e.status == .canceled { count(type, "status.canceled") }
            if (e.calendarItemExternalIdentifier ?? "").contains("/RID=") { count(type, "externalID.withRID") }
            if e.calendarItemExternalIdentifier == nil { count(type, "externalID.nil") }
            if e.hasRecurrenceRules || e.isDetached { count(type, "recurring") }
        }
        let data = (try? JSONSerialization.data(withJSONObject: stats, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("attendance-probe.json")
        try? data.write(to: url)
        return "Probe written to \(url.path)"
    }
}
