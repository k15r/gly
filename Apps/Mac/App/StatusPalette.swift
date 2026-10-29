import SwiftUI
import GlyCore

/// The status palette (specs/appearance "Status colors", status-colors C1): one color and icon per meaning, everywhere.
extension StatusKind {
    var color: Color {
        switch self {
        case .cantFit, .overdue: .red
        case .dueToday: .orange
        case .needsWork: .blue
        case .backFromSnooze: .purple
        case .done: .green
        }
    }

    var symbol: String {
        switch self {
        case .cantFit: "exclamationmark.triangle.fill"
        case .overdue: "exclamationmark.circle.fill"
        case .dueToday: "calendar.badge.clock"
        case .needsWork: "hammer.fill"
        case .backFromSnooze: "moon.zzz.fill"
        case .done: "checkmark.circle.fill"
        }
    }
}
