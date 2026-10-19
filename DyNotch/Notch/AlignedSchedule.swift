import SwiftUI

/// Ticks on whole multiples of `interval` on the clock (every second, every half second…)
/// rather than counting from when the view appeared, so everything in the notch that ticks
/// this way redraws in the same pass. Each pass of its own costs far more than the redraw:
/// with Now Playing's scrubber on screen, a timer ticking once a second out of step with it
/// cost about 5 CPU points, and under 1 in step.
nonisolated struct AlignedSchedule: TimelineSchedule {
    let interval: TimeInterval

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> some Sequence<Date> {
        let first = (startDate.timeIntervalSinceReferenceDate / interval).rounded(.down) * interval
        return sequence(first: Date(timeIntervalSinceReferenceDate: first)) { $0.addingTimeInterval(interval) }
    }
}

extension TimelineSchedule where Self == AlignedSchedule {
    static func aligned(every interval: TimeInterval) -> AlignedSchedule { AlignedSchedule(interval: interval) }
}
