import AppKit
import os
import WorkDashCore

/// "Open in Calendar" (meeting-pages N6). SPIKE: three candidate forms; the winner stays, the menu goes.
enum CalendarOpener {
    enum Form { case eventIdentifier, externalIdentifier, activate }
    private static let log = Logger(subsystem: "dev.k15r.workdash", category: "calendar-open")

    static func open(_ form: Form, _ a: Appointment) {
        var allowed = CharacterSet.urlPathAllowed; allowed.remove(charactersIn: "/:")
        let id: String?
        switch form {
        case .eventIdentifier: id = a.eventIdentifier
        case .externalIdentifier: id = a.identity.baseID
        case .activate: id = nil
        }
        if let id, let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more") {
            log.notice("open \(url.absoluteString, privacy: .public)")
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
