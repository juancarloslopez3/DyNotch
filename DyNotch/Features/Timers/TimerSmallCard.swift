import SwiftUI

/// The clock that's going (the timer, else the Pomodoro, else the stopwatch) in large type,
/// with a button to pause it. When none is, a button that starts the last timer again. With
/// about half the column, on one row.
struct TimerCard: View {
    @Environment(AppServices.self) private var services
    var height = HomeCardHeight.full

    var body: some View {
        let timers = services.timers
        GlassCard(padding: 10) {
            Group {
                if let mode = [TimerMode.timer, .pomodoro, .stopwatch].first(where: timers.isActive) {
                    RunningClockPanel(mode: mode, isCompact: height == .half)
                } else {
                    StartTimerPanel(isCompact: height == .half)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RunningClockPanel: View {
    @Environment(AppServices.self) private var services
    let mode: TimerMode
    let isCompact: Bool

    var body: some View {
        let timers = services.timers
        let isRunning = timers.isRunning(mode)
        let layout = isCompact ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 10))
        layout {
            // Only the ring and the time redraw, once a second in step with the rest of the
            // notch: on the clock's seconds rather than the timer's own.
            Group {
                if isRunning {
                    TimelineView(.aligned(every: 1)) { context in
                        readout(at: context.date, isRunning: true)
                    }
                } else {
                    readout(at: .now, isRunning: false)
                }
            }
            .layoutPriority(1)
            if isCompact {
                Spacer(minLength: 0)
            }
            Button { timers.toggle(mode) } label: {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help(isRunning ? "Pause" : "Resume")
        }
    }

    private func readout(at date: Date, isRunning: Bool) -> some View {
        let timers = services.timers
        let color = mode == .pomodoro ? timers.pomodoroPhase.color : mode.color
        let ring: CGFloat = isCompact ? 30 : 40
        return HStack(spacing: 10) {
            Group {
                switch mode {
                case .timer: ProgressRing(progress: timers.timer.progress(at: date), color: color, lineWidth: 4, animation: nil)
                case .pomodoro: ProgressRing(progress: timers.pomodoro.progress(at: date), color: color, lineWidth: 4, animation: nil)
                case .stopwatch:
                    Image(systemName: "stopwatch.fill")
                        .font(.system(size: ring * 0.7))
                        .foregroundStyle(color)
                }
            }
            .frame(width: ring, height: ring)
            VStack(alignment: .leading, spacing: 1) {
                Text(timers.clockText(mode, at: date))
                    .font(.system(size: isCompact ? 20 : 24, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                    .opacity(isRunning ? 1 : 0.5)
                Text(isRunning ? (mode == .pomodoro ? timers.pomodoroPhase.title : mode.title) : String(localized: "Paused"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

/// A button that starts a timer as long as the last one, under the symbol, or beside it on one row.
private struct StartTimerPanel: View {
    let isCompact: Bool

    var body: some View {
        let layout = isCompact ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
        layout {
            Image(systemName: "timer")
                .font(.system(size: isCompact ? 18 : 26, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            if isCompact {
                Spacer(minLength: 4)
            }
            StartTimerButton(isCompact: isCompact)
        }
    }
}

/// The clock that's going (the timer, else the Pomodoro, else the stopwatch) with a button to
/// pause it when there's room. When none is, a button that starts the last timer again.
struct TimerSmallCard: View {
    @Environment(AppServices.self) private var services
    let isNarrow: Bool

    var body: some View {
        let timers = services.timers
        SmallWidgetCard {
            if let mode = [TimerMode.timer, .pomodoro, .stopwatch].first(where: timers.isActive) {
                RunningClockRow(mode: mode, isNarrow: isNarrow)
            } else {
                StartTimerRow(isNarrow: isNarrow)
            }
        }
    }
}

private struct RunningClockRow: View {
    @Environment(AppServices.self) private var services
    let mode: TimerMode
    let isNarrow: Bool

    var body: some View {
        let timers = services.timers
        let isRunning = timers.isRunning(mode)
        HStack(spacing: 8) {
            // Only the ring and the time redraw, once a second in step with the rest of the
            // notch: on the clock's seconds rather than the timer's own.
            Group {
                if isRunning {
                    TimelineView(.aligned(every: 1)) { context in
                        readout(at: context.date, isRunning: true)
                    }
                } else {
                    readout(at: .now, isRunning: false)
                }
            }
            .help(mode == .pomodoro ? "Pomodoro · \(timers.pomodoroPhase.title)" : mode.title)
            .layoutPriority(1)
            if !isNarrow {
                Spacer(minLength: 4)
                Button { timers.toggle(mode) } label: {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help(isRunning ? "Pause" : "Resume")
            }
        }
    }

    private func readout(at date: Date, isRunning: Bool) -> some View {
        let timers = services.timers
        let color = mode == .pomodoro ? timers.pomodoroPhase.color : mode.color
        return HStack(spacing: isNarrow ? 5 : 7) {
            Group {
                switch mode {
                case .timer: ProgressRing(progress: timers.timer.progress(at: date), color: color, lineWidth: 2.5, animation: nil)
                case .pomodoro: ProgressRing(progress: timers.pomodoro.progress(at: date), color: color, lineWidth: 2.5, animation: nil)
                case .stopwatch:
                    Image(systemName: "stopwatch.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                }
            }
            .frame(width: isNarrow ? 15 : 17, height: isNarrow ? 15 : 17)
            Text(timers.clockText(mode, at: date))
                .font(.system(size: isNarrow ? 14 : 16, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .opacity(isRunning ? 1 : 0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Starts a timer as long as the last one. The name, then the symbol, make way for the button.
private struct StartTimerRow: View {
    let isNarrow: Bool

    var body: some View {
        if isNarrow {
            startButton
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    symbol
                    Text("Timer")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    startButton
                }
                HStack(spacing: 6) {
                    symbol
                    Spacer(minLength: 4)
                    startButton
                }
                startButton
            }
        }
    }

    private var symbol: some View {
        Image(systemName: "timer")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.orange)
    }

    private var startButton: some View {
        StartTimerButton(isCompact: true)
    }
}

/// Starts a timer as long as the last one.
private struct StartTimerButton: View {
    @Environment(AppServices.self) private var services
    let isCompact: Bool

    var body: some View {
        let duration = services.settings.lastTimerDuration
        Button {
            withAnimation(.notchQuick) { services.timers.startTimer(duration: duration) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(TimeFormat.clock(duration))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .buttonStyle(.tintedGlass(.orange, isCompact: isCompact))
        .help("Start a \(TimeFormat.clock(duration)) timer")
    }
}
