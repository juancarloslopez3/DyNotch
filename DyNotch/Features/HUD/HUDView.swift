import SwiftUI

/// Volume / brightness / backlight HUD: icon and percentage beside the notch, a draggable
/// glass level bar below it, and above the bar the display it's about when that isn't plain.
struct HUDView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let snapshot: HUDSnapshot
    let notch: CGSize

    var body: some View {
        VStack(spacing: 0) {
            WingsLayout(notch: notch) {
                ZStack {
                    // One per kind, so going from brightness to volume swaps the sun for the
                    // speaker rather than turning the speaker back from the sun's angle.
                    HUDIcon(snapshot: snapshot)
                        .id(snapshot.kind)
                        .transition(.blurReplace)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 22)
            } trailing: {
                Group {
                    if snapshot.isUnavailable {
                        Text("—")
                    } else {
                        HUDPercent(percent: Int((snapshot.displayLevel * 100).rounded()))
                    }
                }
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 22)
            }

            if let caption = snapshot.caption {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
            }

            if snapshot.isUnavailable {
                Text("This output's volume can't be changed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxHeight: .infinity)
            } else {
                LevelBar(level: snapshot.displayLevel) { level in
                    services.hud.set(snapshot.kind, level: level, target: snapshot.target)
                }
                .frame(height: 8)
                .keyframeAnimator(initialValue: CGFloat.zero, trigger: snapshot.pushes) { bar, stretch in
                    // Pressed on past full or empty: the bar gives a little that way, thinning
                    // as it stretches, and springs back.
                    bar.scaleEffect(
                        x: 1 + stretch * 0.04, y: 1 - stretch * 0.3,
                        anchor: snapshot.displayLevel < 0.5 ? .trailing : .leading
                    )
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(reduceMotion ? 0 : 1, duration: 0.12)
                        SpringKeyframe(0, duration: 0.5, spring: Spring(duration: 0.45, bounce: 0.4))
                    }
                }
                .padding(.horizontal, 22)
                .frame(maxHeight: .infinity)
            }
        }
        .animation(.notchQuick, value: snapshot)
    }
}

/// The level in percent, all its digits rolling to the new one at once. In one `Text` they roll
/// one after another, left to right, so 15 → 20 read 25 on the way and 20 → 15 read 10.
private struct HUDPercent: View {
    let percent: Int

    var body: some View {
        let digits = Array(String(percent))
        HStack(spacing: 0) {
            // Hundreds, tens, units. A place the number doesn't reach is empty, so the 1 of 100
            // rolls in with the zeros rather than fading in beside them.
            ForEach((0..<3).reversed(), id: \.self) { place in
                Text(place < digits.count ? String(digits[digits.count - 1 - place]) : "")
                    .contentTransition(.numericText(value: Double(percent)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent)")
    }
}

/// The level's symbol, moving with it: the speaker's waves fill in and muting draws its slash
/// on in red; the sun turns and grows as the display brightens, the keyboard's light grows.
private struct HUDIcon: View {
    let snapshot: HUDSnapshot
    /// The symbol on screen: the snapshot's, by way of the bare speaker while muting or unmuting.
    @State private var symbol: String
    /// The waves fade in and out over the bare speaker, which stays put under them; replacing
    /// it with them would shrink it away and back.
    @State private var fadesWaves = false
    /// The waves' level, kept as it was when the sound goes off so they fade out as they were.
    @State private var wavesLevel: Float
    /// A level that comes while the last one's waves are still fading (a held key, a drag) shows
    /// at once: fades cut short snapped other waves on and off, or flashed them.
    @State private var wavesJump = false
    @State private var wavesChanged = Date.distantPast

    init(snapshot: HUDSnapshot) {
        self.snapshot = snapshot
        // Coming up muted, as the mute key brings it, it draws the slash on as it drops in.
        _symbol = State(initialValue: snapshot.isSilent ? "speaker.fill" : snapshot.symbol)
        _wavesLevel = State(initialValue: snapshot.displayLevel)
    }

    var body: some View {
        Group {
            if snapshot.kind == .brightness {
                // Its rays' tips on the bar's end.
                SunShape(rays: snapshot.symbol == "sun.max.fill" ? 1 : 0)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: symbol, variableValue: Double(wavesLevel))
                    .contentTransition(fadesWaves ? .opacity : .symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                    // The symbol fades between levels by itself, animation or not, until told to stop.
                    .transaction(value: wavesLevel) { if wavesJump { $0.disablesAnimations = true } }
                    .background(alignment: .leading) {
                        if fadesWaves { Image(systemName: "speaker.fill") }
                    }
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .foregroundStyle(snapshot.isSilent ? Color.red : .white)
        .scaleEffect(snapshot.kind == .volume ? 1 : 0.85 + 0.15 * CGFloat(snapshot.level))
        .rotationEffect(.degrees(snapshot.kind == .brightness ? 180 * Double(snapshot.level) : 0))
        // The sun's middle on the digits', half a point below the middle of their line (the
        // speaker symbol lines up by itself). After the turn, which would swing it sideways.
        .offset(y: snapshot.kind == .brightness ? 0.5 : 0)
        .onChange(of: snapshot.displayLevel) {
            guard !snapshot.isSilent else { return }
            wavesJump = Date.now.timeIntervalSince(wavesChanged) < 0.35
            wavesChanged = .now
            wavesLevel = snapshot.displayLevel
        }
        .task(id: snapshot.symbol) {
            // Straight between the waves and the slash the whole speaker drops out and back, and
            // with the key held down to silence, the waves still dimming flash back on as it
            // goes. So the slash only draws on and off the bare speaker, and the waves fade over
            // it: out before the slash comes, in after it goes.
            let waves = "speaker.wave.3.fill", slash = "speaker.slash.fill", bare = "speaker.fill"
            let target = snapshot.symbol
            if (symbol == waves && target == slash) || (symbol == slash && target == waves) {
                fadesWaves = symbol == waves
                withAnimation(.notchQuick) { symbol = bare }
                try? await Task.sleep(for: .seconds(0.22))
                guard !Task.isCancelled else { return }
            }
            fadesWaves = symbol == bare && target == waves
            withAnimation(.notchQuick) { symbol = target }
        }
    }
}

/// `sun.min.fill` turning into `sun.max.fill` in place, its dots drawing out into rays. The
/// symbols themselves differ in size, so they sat off each other, and only swap by dropping out.
private nonisolated struct SunShape: Shape {
    /// 0 for the dots, 1 for the rays.
    var rays: CGFloat

    var animatableData: CGFloat {
        get { rays }
        set { rays = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Measured off the symbols at 15 pt semibold, in points out from the middle of an
        // 18 pt box: the rays reach its edge.
        let unit = min(rect.width, rect.height) / 18
        func blend(_ dots: CGFloat, _ rays: CGFloat) -> CGFloat { (dots + (rays - dots) * self.rays) * unit }
        let disc = blend(4.14, 4.2)
        let inner = blend(6.06, 5.62), outer = blend(7.94, 8.94), width = blend(1.88, 1.75)
        let ray = Path(
            roundedRect: CGRect(x: inner, y: -width / 2, width: max(outer - inner, width), height: width),
            cornerRadius: width / 2
        )
        var path = Path(ellipseIn: CGRect(x: rect.midX - disc, y: rect.midY - disc, width: disc * 2, height: disc * 2))
        for index in 0..<8 {
            path.addPath(ray, transform: CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .rotated(by: .pi / 4 * CGFloat(index)))
        }
        return path
    }
}

/// A slim glass track with a white fill. Drag or click anywhere to set the level.
struct LevelBar: View {
    let level: Float
    var tint: Color = .white
    let onChange: (Float) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.12))
                    .glassEffect(.regular, in: .capsule)
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.height, width * CGFloat(level)))
                    .opacity(level > 0 ? 1 : 0)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onChange(Float(min(max(value.location.x / width, 0), 1)))
                    }
            )
        }
    }
}
