import Foundation

/// A pausable countdown. All math is based on wall-clock dates so it stays correct
/// across sleep.
nonisolated struct Countdown: Equatable, Sendable {
    var duration: TimeInterval
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval?

    init(duration: TimeInterval) {
        self.duration = duration
    }

    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isActive: Bool { isRunning || isPaused }

    func remaining(at now: Date) -> TimeInterval {
        if let endDate { return max(endDate.timeIntervalSince(now), 0) }
        return pausedRemaining ?? duration
    }

    func progress(at now: Date) -> Double {
        duration > 0 ? 1 - remaining(at: now) / duration : 0
    }

    func isFinished(at now: Date) -> Bool {
        if let endDate { return now >= endDate }
        return false
    }

    mutating func start(at now: Date) {
        pausedRemaining = nil
        endDate = now.addingTimeInterval(duration)
    }

    mutating func pause(at now: Date) {
        guard let endDate else { return }
        pausedRemaining = max(endDate.timeIntervalSince(now), 0)
        self.endDate = nil
    }

    mutating func resume(at now: Date) {
        guard let pausedRemaining else { return }
        endDate = now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
    }

    mutating func add(_ seconds: TimeInterval, at now: Date) {
        duration += seconds
        if let endDate { self.endDate = endDate.addingTimeInterval(seconds) }
        if let pausedRemaining { self.pausedRemaining = pausedRemaining + seconds }
    }

    mutating func reset() {
        endDate = nil
        pausedRemaining = nil
    }
}

nonisolated struct Stopwatch: Equatable, Sendable {
    private(set) var startDate: Date?
    private(set) var accumulated: TimeInterval = 0
    private(set) var laps: [TimeInterval] = []

    var isRunning: Bool { startDate != nil }
    var isActive: Bool { isRunning || accumulated > 0 }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startDate.map { now.timeIntervalSince($0) } ?? 0)
    }

    mutating func start(at now: Date) {
        guard startDate == nil else { return }
        startDate = now
    }

    mutating func pause(at now: Date) {
        guard let startDate else { return }
        accumulated += now.timeIntervalSince(startDate)
        self.startDate = nil
    }

    mutating func lap(at now: Date) {
        laps.insert(elapsed(at: now), at: 0)
    }

    mutating func reset() {
        self = Stopwatch()
    }
}

nonisolated enum PomodoroPhase: Equatable, Sendable {
    case focus(round: Int)
    case shortBreak(afterRound: Int)
    case longBreak

    var isBreak: Bool {
        if case .focus = self { false } else { true }
    }

    var title: String {
        switch self {
        case .focus: String(localized: "Focus")
        case .shortBreak: String(localized: "Short Break")
        case .longBreak: String(localized: "Long Break")
        }
    }

    /// The phase after this one, given the number of focus rounds before a long break.
    func next(rounds: Int) -> PomodoroPhase {
        switch self {
        case .focus(let round): round >= rounds ? .longBreak : .shortBreak(afterRound: round)
        case .shortBreak(let round): .focus(round: round + 1)
        case .longBreak: .focus(round: 1)
        }
    }

    func duration(work: Int, shortBreak: Int, longBreak: Int) -> TimeInterval {
        switch self {
        case .focus: TimeInterval(work * 60)
        case .shortBreak: TimeInterval(shortBreak * 60)
        case .longBreak: TimeInterval(longBreak * 60)
        }
    }
}

nonisolated enum TimeFormat {
    /// 4:05, 1:02:03
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 01:02.34 for the stopwatch.
    static func precise(_ seconds: TimeInterval) -> String {
        let hundredths = Int((seconds * 100).rounded(.down))
        let minutes = hundredths / 6000
        let rest = hundredths % 6000
        return minutes >= 60
            ? String(format: "%d:%02d:%02d.%02d", minutes / 60, minutes % 60, rest / 100, rest % 100)
            : String(format: "%02d:%02d.%02d", minutes, rest / 100, rest % 100)
    }
}
