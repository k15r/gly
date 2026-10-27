import GRDB
import SwiftUI
import WorkDashCore

/// Which meetings have notes, observed once for all day-view rows (meeting-pages N7).
@MainActor
@Observable
final class MeetingMarksModel {
    private(set) var marks = MeetingNotesMarks()
    @ObservationIgnored private var store: ReadOnlyStore?
    @ObservationIgnored private var observation: AnyDatabaseCancellable?

    func attach(_ store: ReadOnlyStore?) {
        guard let store, self.store !== store else { return }
        self.store = store
        observation = store.observe(ValueObservation.tracking { try MeetingNotes.marks($0) },
                                    onError: { print("meeting marks observation: \($0)") },
                                    onChange: { [weak self] in self?.marks = $0 })
    }
}
