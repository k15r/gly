import Foundation
import Observation
import GlyCore

/// Current time for time-based UI state; ticks every 30 s and reports day changes (midnight).
@MainActor
@Observable
final class Clock {
    private(set) var now = Date()
    private(set) var today = LocalDay(date: Date())
    var onDayChange: ((LocalDay) -> Void)?
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func tick() {
        now = Date()
        let d = LocalDay(date: now)
        if d != today {
            today = d
            onDayChange?(d)
        }
    }
}
