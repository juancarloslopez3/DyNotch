import SwiftUI

extension TimerMode {
    var color: Color {
        switch self {
        case .timer: .orange
        case .stopwatch: .cyan
        case .pomodoro: .red
        }
    }
}

extension PomodoroPhase {
    var color: Color { isBreak ? .green : .red }

    var symbol: String {
        switch self {
        case .focus: "brain.head.profile"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "sofa.fill"
        }
    }
}

/// Every clock sits in a dial this size, so switching modes doesn't move things around.
private let dialSize: CGFloat = 118

struct TimersTabView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var timers = services.timers
        HStack(spacing: 10) {
            ModeSwitcher(mode: $timers.mode)
                .frame(width: 132)
            GlassCard(padding: 14) {
                switch timers.mode {
                case .timer: TimerPanel()
                case .stopwatch: StopwatchPanel()
                case .pomodoro: PomodoroPanel()
                }
            }
        }
    }
}

/// Mode list, in the order the user dragged it into. A clock that's going shows its time under
/// its name, with a dot that's filled while it runs and hollow while paused.
private struct ModeSwitcher: View {
    @Environment(AppServices.self) private var services
    @Binding var mode: TimerMode
    @Namespace private var namespace

    var body: some View {
        @Bindable var settings = services.settings
        ReorderableStack(items: $settings.timerOrder, axis: .vertical, spacing: 4) { item in
            ModeRow(item: item, mode: $mode, namespace: namespace)
        }
    }
}

private struct ModeRow: View {
    @Environment(AppServices.self) private var services
    @Environment(\.isReorderCopy) private var isReorderCopy
    let item: TimerMode
    @Binding var mode: TimerMode
    let namespace: Namespace.ID

    var body: some View {
        let timers = services.timers
        let isActive = timers.isActive(item)
        let isRunning = timers.isRunning(item)
        let tint = item == .pomodoro ? timers.pomodoroPhase.color : item.color
        HStack(spacing: 8) {
            Image(systemName: item.symbol)
                .frame(width: 16)
                .foregroundStyle(mode == item ? tint : .white.opacity(0.5))
                .accessibilityHidden(true)
            // Room for "Stopwatch" beside the dot; never wrap.
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                if isActive {
                    // Only the time redraws (not the row's glass), once a second.
                    Group {
                        if let anchor = timers.tickAnchor(item) {
                            TimelineView(.periodic(from: anchor, by: 1)) { context in
                                Text(timers.clockText(item, at: context.date))
                            }
                        } else {
                            Text(timers.clockText(item, at: .now))
                        }
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint.opacity(isRunning ? 1 : 0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isActive {
                Circle()
                    .strokeBorder(tint, lineWidth: 1.5)
                    .background(Circle().fill(isRunning ? tint : .clear))
                    .frame(width: 6, height: 6)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(mode == item ? .white : .white.opacity(0.6))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if mode == item {
                let glass = RoundedRectangle(cornerRadius: 14).fill(.clear)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                if isReorderCopy {
                    glass
                } else {
                    glass.matchedGeometryEffect(id: "mode", in: namespace)
                }
            }
        }
        .contentShape(.rect)
        // A tap, like the tabs in Settings › Layout's preview, so a drag that starts on a row
        // goes to the list and reorders it.
        .onTapGesture { select() }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select() }
    }

    private func select() {
        withAnimation(.notchQuick) { mode = item }
    }
}

// MARK: - Timer

/// Set up inside the dial, then the same dial counts down. Presets only fill in the
/// picker, so seconds or minutes can still be adjusted before starting.
private struct TimerPanel: View {
    @Environment(AppServices.self) private var services
    @State private var seconds = 5 * 60

    private static let presets = [1, 3, 5, 10, 15, 30, 45, 60]

    var body: some View {
        let timers = services.timers
        let timer = timers.timer
        HStack(spacing: 22) {
            if timer.isActive {
                CountdownDial(countdown: timer, color: .orange)
            } else {
                Dial(progress: 0, color: .orange) {
                    DurationPicker(seconds: $seconds)
                        .onAppear {
                            seconds = DurationPicker.clamped(Int(services.settings.lastTimerDuration.rounded()))
                        }
                }
            }
            Group {
                if timer.isActive {
                    running(timers)
                } else {
                    setup(timers)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private func setup(_ timers: TimerStore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(50), spacing: 6), count: 4), spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button("\(preset)m") {
                        withAnimation(.notchQuick) { seconds = preset * 60 }
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: seconds == preset * 60, tint: .orange))
                }
            }
            .frame(width: 218)
            HStack(spacing: 12) {
                Button {
                    withAnimation(.notchQuick) { timers.startTimer(duration: TimeInterval(seconds)) }
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(width: 76)
                }
                .buttonStyle(.tintedGlass(.orange))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    EndTime(date: context.date.addingTimeInterval(TimeInterval(seconds)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func running(_ timers: TimerStore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Timer")
                    .font(.system(size: 15, weight: .semibold))
                Text(durationText(timers.timer.duration))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ControlButton(symbol: timers.timer.isRunning ? "pause.fill" : "play.fill", prominent: true, tint: .orange) {
                    timers.toggleTimer()
                }
                ControlButton(symbol: "plus", label: "1 min") { timers.addToTimer(60) }
                ControlButton(symbol: "xmark") {
                    withAnimation(.notchQuick) { timers.cancelTimer() }
                }
                .help("Cancel")
            }
        }
    }
}

/// Minutes and seconds, each with arrows above and below. Steps carry over (0:55 up
/// is 1:00), and holding an arrow keeps stepping.
private struct DurationPicker: View {
    @Binding var seconds: Int

    private static let secondStep = 5
    private static let range = secondStep...(180 * 60)

    static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, range.lowerBound), range.upperBound)
    }

    var body: some View {
        HStack(spacing: 2) {
            column(String(seconds / 60), step: 60, add: "Add a minute", remove: "Remove a minute")
            Text(":")
            column(String(format: "%02d", seconds % 60), step: Self.secondStep,
                   add: "Add \(Self.secondStep) seconds", remove: "Remove \(Self.secondStep) seconds")
        }
        // Small enough that 180:00 still fits inside the dial.
        .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
        .fixedSize()
    }

    private func column(_ text: String, step: Int, add: LocalizedStringKey, remove: LocalizedStringKey) -> some View {
        VStack(spacing: 0) {
            StepArrow(symbol: "chevron.up") { self.step(by: step) }
                .disabled(!Self.range.contains(seconds + step))
                .accessibilityLabel(add)
            Text(text)
                .contentTransition(.numericText(value: Double(seconds)))
            StepArrow(symbol: "chevron.down") { self.step(by: -step) }
                .disabled(!Self.range.contains(seconds - step))
                .accessibilityLabel(remove)
        }
    }

    private func step(by delta: Int) {
        guard Self.range.contains(seconds + delta) else { return }
        withAnimation(.notchQuick) { seconds += delta }
    }
}

private struct StepArrow: View {
    let symbol: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 18)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .foregroundStyle(.white.opacity(isEnabled ? (isHovered ? 0.9 : 0.4) : 0.12))
        .onHover { isHovered = $0 }
    }
}

// MARK: - Stopwatch

private struct StopwatchPanel: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let timers = services.timers
        let stopwatch = timers.stopwatch
        // Lap while running; once paused the same button resets.
        let laps = stopwatch.isRunning || !stopwatch.isActive
        // Only the hand, the time and the current lap redraw while it runs, each in a
        // fixed frame so the rest of the notch isn't laid out again every frame.
        HStack(spacing: 22) {
            StopwatchDial(stopwatch: stopwatch)
            VStack(alignment: .leading, spacing: 14) {
                StopwatchTimeline(stopwatch: stopwatch) { elapsed in
                    PreciseTime(seconds: elapsed)
                }
                .frame(width: 170, height: 42, alignment: .leading)
                HStack(spacing: 10) {
                    ControlButton(symbol: stopwatch.isRunning ? "pause.fill" : "play.fill", prominent: true, tint: .cyan) {
                        timers.toggleStopwatch()
                    }
                    ControlButton(symbol: laps ? "flag.fill" : "arrow.counterclockwise", label: laps ? "Lap" : "Reset") {
                        timers.lapOrResetStopwatch()
                    }
                    .disabled(!stopwatch.isActive)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LapList(stopwatch: stopwatch)
                .frame(width: 140)
        }
    }
}

/// Redraws its content every frame while the stopwatch runs.
private struct StopwatchTimeline<Content: View>: View {
    let stopwatch: Stopwatch
    @ViewBuilder var content: (TimeInterval) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !stopwatch.isRunning)) { context in
            content(stopwatch.elapsed(at: context.date))
        }
    }
}

/// Analog face with a seconds hand that sweeps once a minute.
private struct StopwatchDial: View {
    let stopwatch: Stopwatch

    private static let handTip: CGFloat = dialSize / 2 - 8
    private static let handTail: CGFloat = 12

    var body: some View {
        ZStack {
            DialFace()
            StopwatchTimeline(stopwatch: stopwatch) { elapsed in
                Capsule()
                    .fill(.cyan)
                    .frame(width: 2, height: Self.handTip + Self.handTail)
                    .offset(y: -(Self.handTip - Self.handTail) / 2)
                    .rotationEffect(.degrees(elapsed.truncatingRemainder(dividingBy: 60) * 6))
            }
            Circle()
                .fill(.cyan)
                .frame(width: 8, height: 8)
            Circle()
                .fill(.black)
                .frame(width: 3, height: 3)
        }
        .frame(width: dialSize, height: dialSize)
        .background(.white.opacity(0.05), in: .circle)
    }
}

/// Ticks and numbers. No inputs, so it's drawn once rather than every frame.
private struct DialFace: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            // `fraction` of a turn clockwise from 12 o'clock.
            func point(_ fraction: Double, _ distance: CGFloat) -> CGPoint {
                let angle = fraction * 2 * .pi
                return CGPoint(x: center.x + sin(angle) * distance, y: center.y - cos(angle) * distance)
            }

            for tick in 0..<60 {
                let major = tick % 5 == 0
                var path = Path()
                path.move(to: point(Double(tick) / 60, radius - 4))
                path.addLine(to: point(Double(tick) / 60, radius - (major ? 12 : 8)))
                context.stroke(
                    path,
                    with: .color(.white.opacity(major ? 0.6 : 0.22)),
                    style: StrokeStyle(lineWidth: major ? 2 : 1, lineCap: .round)
                )
            }
            for number in stride(from: 15, through: 60, by: 15) {
                let label = Text("\(number)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                context.draw(label, at: point(Double(number) / 60, radius - 22))
            }
        }
    }
}

/// 01:02 large with the hundredths smaller beside it. A set size rather than
/// shrink-to-fit, which would measure the text over and over on every frame.
private struct PreciseTime: View {
    let seconds: TimeInterval

    var body: some View {
        let text = TimeFormat.precise(seconds)
        let split = text.lastIndex(of: ".") ?? text.endIndex
        let size: CGFloat = seconds >= 3600 ? 26 : 34
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(text[..<split])
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
            Text(text[split...])
                .font(.system(size: size * 0.65, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}

/// The lap in progress pinned on top, then finished laps with the fastest in green
/// and the slowest in red.
private struct LapList: View {
    let stopwatch: Stopwatch

    var body: some View {
        Group {
            if stopwatch.isActive {
                VStack(spacing: 6) {
                    StopwatchTimeline(stopwatch: stopwatch) { elapsed in
                        LapRow(number: stopwatch.laps.count + 1, time: elapsed - (stopwatch.laps.first ?? 0))
                    }
                    // A scroll view costs a lot to keep on screen beside a running clock,
                    // so there's none until there are laps to scroll.
                    if !stopwatch.laps.isEmpty {
                        FinishedLaps(laps: stopwatch.laps)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "flag")
                        .font(.system(size: 14))
                    Text("No laps yet")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}

/// Its own view outside the per-frame redraw, so it only updates when a lap is added.
private struct FinishedLaps: View {
    let laps: [TimeInterval]

    var body: some View {
        let splits = Self.splits(laps)
        let best = splits.count > 1 ? splits.min() : nil
        let worst = splits.count > 1 ? splits.max() : nil
        ScrollView(.vertical) {
            VStack(spacing: 6) {
                ForEach(Array(splits.enumerated()), id: \.offset) { index, split in
                    let color: Color = best == worst ? .white : split == best ? .green : split == worst ? .red : .white
                    LapRow(number: splits.count - index, time: split, color: color)
                }
            }
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
    }

    /// Laps are stored as total times, newest first. This is each lap's own length.
    static func splits(_ laps: [TimeInterval]) -> [TimeInterval] {
        laps.indices.map { laps[$0] - (laps.indices.contains($0 + 1) ? laps[$0 + 1] : 0) }
    }
}

private struct LapRow: View {
    let number: Int
    let time: TimeInterval
    var color: Color = .white

    var body: some View {
        HStack {
            Text("Lap \(number)")
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(TimeFormat.precise(time))
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 66, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .frame(height: 14)
    }
}

// MARK: - Pomodoro

private struct PomodoroPanel: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let timers = services.timers
        let pomodoro = timers.pomodoro
        let phase = timers.pomodoroPhase
        let rounds = services.settings.pomodoroRounds
        let next = phase.next(rounds: rounds)
        HStack(spacing: 22) {
            CountdownDial(countdown: pomodoro, color: phase.color, symbol: phase.symbol)
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(phase.title)
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 8) {
                        // The current round's bar only creeps along; every 10 s is plenty.
                        TimelineView(.animation(minimumInterval: 10, paused: !pomodoro.isRunning)) { context in
                            RoundDots(phase: phase, rounds: rounds, progress: pomodoro.progress(at: context.date))
                        }
                        Text(timers.pomodoroRoundText)
                            .foregroundStyle(.secondary)
                    }
                    Text("Up next: \(next.title) · \(durationText(timers.pomodoroDuration(for: next)))")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 11))
                HStack(spacing: 10) {
                    ControlButton(symbol: pomodoro.isRunning ? "pause.fill" : "play.fill", prominent: true, tint: phase.color) {
                        timers.togglePomodoro()
                    }
                    ControlButton(symbol: "forward.end.fill") { timers.skipPomodoroPhase() }
                        .help("Skip to \(next.title)")
                    ControlButton(symbol: "arrow.counterclockwise") { timers.resetPomodoro() }
                        .help("Start over")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }
}

/// One dot per focus round: done rounds filled, the current one wider and filling up. Past
/// eight rounds only the eight around the current one show, so they fit.
private struct RoundDots: View {
    let phase: PomodoroPhase
    let rounds: Int
    let progress: Double

    private static let maxDots = 8

    var body: some View {
        HStack(spacing: 4) {
            ForEach(shownRounds, id: \.self) { round in
                let width: CGFloat = isCurrent(round) ? 18 : 7
                Capsule()
                    .fill(.white.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(PomodoroPhase.focus(round: round).color)
                            .frame(width: width * fill(round))
                    }
                    .clipShape(.capsule)
                    .frame(width: width, height: 7)
            }
        }
    }

    private var shownRounds: ClosedRange<Int> {
        let rounds = max(rounds, 1)
        guard rounds > Self.maxDots else { return 1...rounds }
        let current = switch phase {
        case .focus(let round): round
        case .shortBreak(let after): after + 1
        case .longBreak: rounds
        }
        let first = min(max(current - Self.maxDots / 2, 1), rounds - Self.maxDots + 1)
        return first...(first + Self.maxDots - 1)
    }

    private func isCurrent(_ round: Int) -> Bool {
        if case .focus(let current) = phase { current == round } else { false }
    }

    private func fill(_ round: Int) -> Double {
        switch phase {
        case .focus(let current): round < current ? 1 : round == current ? min(max(progress, 0), 1) : 0
        case .shortBreak(let after): round <= after ? 1 : 0
        case .longBreak: 1
        }
    }
}

// MARK: - Shared pieces

/// The ring a countdown sits in.
private struct Dial<Content: View>: View {
    let progress: Double
    let color: Color
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            ProgressRing(progress: progress, color: color, lineWidth: 7)
                .shadow(color: color.opacity(0.45), radius: 6)
            content
        }
        .frame(width: dialSize, height: dialSize)
    }
}

/// A countdown's ring with the time inside. Only this redraws while it counts down.
private struct CountdownDial: View {
    let countdown: Countdown
    let color: Color
    var symbol: String? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !countdown.isRunning)) { context in
            Dial(progress: countdown.progress(at: context.date), color: color) {
                CountdownReadout(countdown: countdown, date: context.date, symbol: symbol, color: color)
            }
        }
    }
}

/// Remaining time inside a dial, with when it ends (or "Paused") underneath.
private struct CountdownReadout: View {
    let countdown: Countdown
    let date: Date
    var symbol: String? = nil
    var color: Color = .white

    var body: some View {
        let remaining = countdown.remaining(at: date)
        VStack(spacing: 1) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.bottom, 1)
            }
            Text(TimeFormat.clock(remaining))
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .opacity(countdown.isPaused ? 0.5 : 1)
            Group {
                if countdown.isRunning {
                    EndTime(date: date.addingTimeInterval(remaining))
                } else {
                    // Kept (hidden) before the first start so the time doesn't jump.
                    Text("Paused").opacity(countdown.isPaused ? 1 : 0)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
    }
}

/// 🔔 3:47 PM
private struct EndTime: View {
    let date: Date

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bell.fill")
                .imageScale(.small)
            Text(date.formatted(date: .omitted, time: .shortened))
        }
        .lineLimit(1)
    }
}

/// "1 min, 45 sec"
private func durationText(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds.rounded())
        .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
}

/// Small glass capsule; tinted when it matches the current value.
private struct ChipButtonStyle: ButtonStyle {
    var isSelected: Bool
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(tint.opacity(isSelected ? 0.6 : 0), in: .capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
            .brightness(configuration.isPressed ? -0.1 : 0)
    }
}

struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 4
    /// How it eases from one value to the next. A ring that moves once a second on glass is
    /// better off without: each ease redraws the glass on every frame.
    var animation: Animation? = .linear(duration: 0.25)

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animation, value: progress)
        }
    }
}

private struct ControlButton: View {
    let symbol: String
    var label: LocalizedStringKey? = nil
    var prominent = false
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        let content = Group {
            if let label {
                Label(label, systemImage: symbol).padding(.horizontal, 4)
            } else {
                Image(systemName: symbol).frame(width: 18)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .frame(height: 22)

        if prominent {
            Button(action: action) { content }
                .buttonStyle(.tintedGlass(tint ?? .accentColor))
        } else {
            Button(action: action) { content }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
    }
}

// MARK: - Compact & live activity

/// Ring on the left of the notch, remaining time on the right.
struct CompactTimerView: View {
    @Environment(AppServices.self) private var services
    let notch: CGSize

    var body: some View {
        let timers = services.timers
        let mode = timers.compactMode ?? .timer
        let color: Color = mode == .pomodoro && timers.pomodoroPhase.isBreak ? .green : mode.color
        TimelineView(.periodic(from: .now, by: mode == .stopwatch ? 0.1 : 0.5)) { context in
            WingsLayout(notch: notch) {
                Group {
                    switch mode {
                    case .timer: ProgressRing(progress: timers.timer.progress(at: context.date), color: color, lineWidth: 3)
                    case .pomodoro: ProgressRing(progress: timers.pomodoro.progress(at: context.date), color: color, lineWidth: 3)
                    case .stopwatch:
                        Image(systemName: "stopwatch.fill").font(.system(size: 13)).foregroundStyle(color)
                    }
                }
                .frame(width: 16, height: 16)
            } trailing: {
                Text(text(mode, at: context.date))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func text(_ mode: TimerMode, at date: Date) -> String {
        let timers = services.timers
        return switch mode {
        case .timer: TimeFormat.clock(timers.timer.remaining(at: date))
        case .pomodoro: TimeFormat.clock(timers.pomodoro.remaining(at: date))
        case .stopwatch: TimeFormat.clock(timers.stopwatch.elapsed(at: date))
        }
    }
}

/// The clock that's going, in its bubble beside the notch: only the time, in the clock's color.
struct MinimalTimerView: View {
    @Environment(AppServices.self) private var services
    let height: CGFloat

    var body: some View {
        let timers = services.timers
        let mode = timers.compactMode ?? .timer
        Group {
            // On the clock's seconds, in step with the rest of the notch.
            if timers.isRunning(mode) {
                TimelineView(.aligned(every: 1)) { context in
                    readout(timers.clockText(mode, at: context.date))
                }
            } else {
                readout(timers.clockText(mode, at: .now))
                    .opacity(0.5)
            }
        }
        .foregroundStyle(mode == .pomodoro ? timers.pomodoroPhase.color : mode.color)
    }

    private func readout(_ time: String) -> some View {
        Text(time)
            .font(.system(size: (height / 2).rounded(), weight: .semibold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
    }
}

struct TimerFinishedView: View {
    @Environment(AppServices.self) private var services
    let event: TimerFinishedEvent
    let notch: CGSize
    @State private var bounce = 0

    var body: some View {
        VStack(spacing: 0) {
            WingsLayout(notch: notch) {
                Image(systemName: event.mode.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(event.mode.color)
                    .symbolEffect(.bounce, value: bounce)
            } trailing: {
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(event.mode.color)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 13, weight: .semibold))
                    Text(event.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if event.mode == .timer {
                    Button("Again") {
                        services.timers.startTimer(duration: services.settings.lastTimerDuration)
                        services.timers.dismissFinished()
                    }
                    .buttonStyle(.glass)
                }
                Button(services.timers.isRinging ? "Stop" : "OK") { services.timers.dismissFinished() }
                    .buttonStyle(.tintedGlass(event.mode.color))
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        }
        .task {
            // A few bounces, and on for as long as the alarm rings.
            var bounces = 0
            while !Task.isCancelled, bounces < 3 || services.timers.isRinging {
                bounce += 1
                bounces += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
