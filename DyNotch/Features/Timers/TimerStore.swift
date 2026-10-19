import AppKit
import Observation
import UserNotifications

enum TimerMode: String, CaseIterable, Identifiable {
    case timer, stopwatch, pomodoro
    var id: String { rawValue }
    var title: String {
        switch self {
        case .timer: String(localized: "Timer")
        case .stopwatch: String(localized: "Stopwatch")
        case .pomodoro: String(localized: "Pomodoro")
        }
    }
    var symbol: String {
        switch self {
        case .timer: "timer"
        case .stopwatch: "stopwatch.fill"
        case .pomodoro: "brain.head.profile"
        }
    }
}

struct TimerFinishedEvent: Equatable {
    var title: String
    var detail: String
    var mode: TimerMode
}

/// Timer, stopwatch and Pomodoro state, plus completion alerts.
@Observable
final class TimerStore {
    var mode: TimerMode = .timer
    private(set) var timer = Countdown(duration: 5 * 60)
    private(set) var stopwatch = Stopwatch()
    private(set) var pomodoro = Countdown(duration: 25 * 60)
    private(set) var pomodoroPhase = PomodoroPhase.focus(round: 1)
    /// A finished timer's alarm is ringing, until it's stopped.
    private(set) var isRinging = false

    @ObservationIgnored private weak var services: AppServices?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private let alarm = AlarmPlayer()
    @ObservationIgnored private var alarmTask: Task<Void, Never>?

    /// How long an alarm rings when nobody stops it.
    static let alarmLimit: Duration = .seconds(5 * 60)

    /// Shown beside the closed notch while counting down. The stopwatch only counts
    /// when it is running.
    var isRunning: Bool { timer.isActive || pomodoro.isActive || stopwatch.isRunning }

    /// Which clock the compact view should show.
    var compactMode: TimerMode? {
        if timer.isActive { return .timer }
        if pomodoro.isActive { return .pomodoro }
        if stopwatch.isRunning { return .stopwatch }
        return nil
    }

    func isActive(_ mode: TimerMode) -> Bool {
        switch mode {
        case .timer: timer.isActive
        case .stopwatch: stopwatch.isActive
        case .pomodoro: pomodoro.isActive
        }
    }

    func isRunning(_ mode: TimerMode) -> Bool {
        switch mode {
        case .timer: timer.isRunning
        case .stopwatch: stopwatch.isRunning
        case .pomodoro: pomodoro.isRunning
        }
    }

    /// Pauses or resumes (or starts) a clock.
    func toggle(_ mode: TimerMode) {
        switch mode {
        case .timer: toggleTimer()
        case .stopwatch: toggleStopwatch()
        case .pomodoro: togglePomodoro()
        }
    }

    /// What a clock shows to the second: the time left of a countdown, the stopwatch's
    /// whole seconds.
    func clockText(_ mode: TimerMode, at date: Date) -> String {
        switch mode {
        case .timer: TimeFormat.clock(timer.remaining(at: date))
        case .stopwatch: TimeFormat.clock(stopwatch.elapsed(at: date).rounded(.down))
        case .pomodoro: TimeFormat.clock(pomodoro.remaining(at: date))
        }
    }

    /// Just after the shown second last turned over, so a once-a-second timeline lands
    /// right as each second changes rather than up to a second late. Nil when stopped.
    func tickAnchor(_ mode: TimerMode) -> Date? {
        let turn: Date? = switch mode {
        case .timer: timer.endDate
        case .stopwatch: stopwatch.startDate?.addingTimeInterval(-stopwatch.accumulated)
        case .pomodoro: pomodoro.endDate
        }
        return turn.map { $0.addingTimeInterval(-($0.timeIntervalSinceNow.rounded(.up) + 1) + 0.01) }
    }

    private var settings: AppSettings? { services?.settings }

    func start(services: AppServices) {
        self.services = services
        timer = Countdown(duration: services.settings.lastTimerDuration)
        pomodoro = Countdown(duration: pomodoroDuration(for: pomodoroPhase))
    }

    // MARK: - Timer

    func startTimer(duration: TimeInterval) {
        settings?.lastTimerDuration = duration
        timer = Countdown(duration: duration)
        timer.start(at: .now)
        scheduleNotification(id: "timer", title: String(localized: "Timer Done"), body: String(localized: "\(TimeFormat.clock(duration)) timer finished"), at: timer)
        startTicking()
    }

    func toggleTimer() {
        if timer.isRunning {
            timer.pause(at: .now)
            cancelNotification(id: "timer")
        } else if timer.isPaused {
            timer.resume(at: .now)
            scheduleNotification(id: "timer", title: String(localized: "Timer Done"), body: String(localized: "Your timer finished"), at: timer)
            startTicking()
        } else {
            startTimer(duration: timer.duration)
        }
    }

    func addToTimer(_ seconds: TimeInterval) {
        timer.add(seconds, at: .now)
        if timer.isRunning {
            scheduleNotification(id: "timer", title: String(localized: "Timer Done"), body: String(localized: "Your timer finished"), at: timer)
        }
    }

    func cancelTimer() {
        timer.reset()
        cancelNotification(id: "timer")
    }

    // MARK: - Stopwatch

    func toggleStopwatch() {
        stopwatch.isRunning ? stopwatch.pause(at: .now) : stopwatch.start(at: .now)
    }

    func lapOrResetStopwatch() {
        stopwatch.isRunning ? stopwatch.lap(at: .now) : stopwatch.reset()
    }

    // MARK: - Pomodoro

    func togglePomodoro() {
        if pomodoro.isRunning {
            pomodoro.pause(at: .now)
            cancelNotification(id: "pomodoro")
        } else {
            if pomodoro.isPaused {
                pomodoro.resume(at: .now)
            } else {
                pomodoro = Countdown(duration: pomodoroDuration(for: pomodoroPhase))
                pomodoro.start(at: .now)
            }
            schedulePomodoroNotification()
            startTicking()
        }
    }

    func skipPomodoroPhase() {
        advancePomodoro(autoStart: pomodoro.isRunning)
    }

    func resetPomodoro() {
        pomodoroPhase = .focus(round: 1)
        pomodoro = Countdown(duration: pomodoroDuration(for: pomodoroPhase))
        cancelNotification(id: "pomodoro")
    }

    private func advancePomodoro(autoStart: Bool) {
        pomodoroPhase = pomodoroPhase.next(rounds: settings?.pomodoroRounds ?? 4)
        pomodoro = Countdown(duration: pomodoroDuration(for: pomodoroPhase))
        cancelNotification(id: "pomodoro")
        if autoStart {
            pomodoro.start(at: .now)
            schedulePomodoroNotification()
            startTicking()
        }
    }

    func pomodoroDuration(for phase: PomodoroPhase) -> TimeInterval {
        phase.duration(
            work: settings?.pomodoroWorkMinutes ?? 25,
            shortBreak: settings?.pomodoroShortBreakMinutes ?? 5,
            longBreak: settings?.pomodoroLongBreakMinutes ?? 15
        )
    }

    var pomodoroRoundText: String {
        let rounds = settings?.pomodoroRounds ?? 4
        return switch pomodoroPhase {
        case .focus(let round): String(localized: "Round \(round) of \(rounds)")
        case .shortBreak(let round): String(localized: "After round \(round)")
        case .longBreak: String(localized: "All \(rounds) rounds done")
        }
    }

    // MARK: - Completion

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self else { return }
                self.checkCompletion()
                if !self.timer.isRunning && !self.pomodoro.isRunning {
                    self.tickTask = nil
                    return
                }
            }
        }
    }

    private func checkCompletion() {
        let now = Date.now
        if timer.isFinished(at: now) {
            let duration = timer.duration
            timer.reset()
            finished(TimerFinishedEvent(title: String(localized: "Timer Done"), detail: String(localized: "\(TimeFormat.clock(duration)) timer"), mode: .timer))
        }
        if pomodoro.isFinished(at: now) {
            let ended = pomodoroPhase
            advancePomodoro(autoStart: true)
            let next = pomodoroPhase
            finished(TimerFinishedEvent(
                title: ended.isBreak ? String(localized: "Break's Over") : String(localized: "Time for a Break"),
                detail: "\(next.title) · \(TimeFormat.clock(pomodoroDuration(for: next)))",
                mode: .pomodoro
            ))
        }
    }

    private func finished(_ event: TimerFinishedEvent) {
        if settings?.timerSound ?? true {
            if settings?.timerAlarm ?? false {
                ring()
            } else {
                NSSound(named: "Glass")?.play()
            }
        }
        Haptics.perform(.levelChange)
        // A ringing alarm stays up until it's stopped.
        services?.activities.post(LiveActivity(id: "timer-done", kind: .timerFinished(event), duration: isRinging ? nil : 12))
    }

    private func ring() {
        alarm.play(AlarmTone(id: settings?.timerAlarmTone ?? AlarmTone.standard.id), repeating: true)
        isRinging = true
        alarmTask?.cancel()
        alarmTask = Task { [weak self] in
            try? await Task.sleep(for: Self.alarmLimit)
            guard !Task.isCancelled else { return }
            self?.dismissFinished()
        }
    }

    /// Takes down a finished timer's alert, stopping its alarm.
    func dismissFinished() {
        alarmTask?.cancel()
        alarmTask = nil
        alarm.stop()
        isRinging = false
        services?.activities.dismiss(id: "timer-done")
    }

    // MARK: - Notifications

    private func schedulePomodoroNotification() {
        let next = pomodoroPhase.next(rounds: settings?.pomodoroRounds ?? 4)
        scheduleNotification(
            id: "pomodoro",
            title: pomodoroPhase.isBreak ? String(localized: "Break's Over") : String(localized: "Time for a Break"),
            body: String(localized: "Up next: \(next.title)"),
            at: pomodoro
        )
    }

    private func scheduleNotification(id: String, title: String, body: String, at countdown: Countdown) {
        guard settings?.timerNotification ?? false else { return }
        let remaining = countdown.remaining(at: .now)
        guard remaining > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil // DyNotch plays its own sound
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
