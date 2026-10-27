import Foundation

/// An appointment's description split for display (meeting-pages N5): the agenda, the folded dial-in block and the
/// join link. Computed live from the calendar's text; never stored.
public struct MeetingDescription: Equatable {
    /// What the organizer wrote, without the dial-in block; empty if there's nothing else.
    public let agenda: String
    /// The Teams/Zoom/... boilerplate (join instructions, phone numbers), shown folded.
    public let dialIn: String?
    /// The meeting link for the Join button.
    public let joinURL: URL?
    /// "Teams meeting", "Zoom meeting", ... for the folded line and the button.
    public let service: String?

    static let services: [(pattern: String, name: String)] = [
        (#"https://teams\.microsoft\.com/l/meetup-join/[^\s<>"]+"#, "Teams"),
        (#"https://teams\.live\.com/meet/[^\s<>"]+"#, "Teams"),
        (#"https://[\w.-]*zoom\.us/j/[^\s<>"]+"#, "Zoom"),
        (#"https://meet\.google\.com/[a-z0-9-]+"#, "Google Meet"),
        (#"https://[\w.-]*webex\.com/[^\s<>"]+"#, "Webex"),
    ]

    public static func parse(notes: String?, location: String?, url: URL?) -> MeetingDescription {
        let text = (notes ?? "").replacingOccurrences(of: "\r\n", with: "\n")
        var join: (URL, String)?
        for source in [location ?? "", url?.absoluteString ?? "", text] where join == nil {
            for s in services {
                if let r = source.range(of: s.pattern, options: .regularExpression), let u = URL(string: String(source[r])) {
                    join = (u, s.name); break
                }
            }
        }
        // The dial-in block starts at a long underscore separator or a service heading line.
        let lines = text.components(separatedBy: "\n")
        let start = lines.firstIndex { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("________") || t.range(of: #"^(Microsoft Teams|Join Zoom Meeting|Join with Google Meet)"#, options: .regularExpression) != nil
        }
        let agendaLines = start.map { Array(lines[..<$0]) } ?? lines
        let dialLines = start.map { Array(lines[$0...]) } ?? []
        let agenda = agendaLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let dial = dialLines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("____") }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return MeetingDescription(agenda: agenda, dialIn: dial.isEmpty ? nil : dial, joinURL: join?.0, service: join?.1)
    }
}
