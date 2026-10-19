import SwiftUI

/// AirPods connecting: the notch drops down and plays them in, then each battery ring fills to
/// its level. Earbuds pop out of their case and land either side of it; AirPods Max turn into
/// view like on a turntable and send out a few sound waves.
struct AirPodsActivityView: View {
    let event: BluetoothEvent
    let model: AirPodsModel
    let notch: CGSize

    var body: some View {
        VStack(spacing: 0) {
            WingsLayout(notch: notch) {
                // The name macOS shows, or just the model's where that doesn't fit beside the
                // notch ("AirPods Pro 2 de Carlos" → "AirPods Pro").
                ViewThatFits(in: .horizontal) {
                    Text(event.name)
                    Text(model.name)
                }
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
            } trailing: {
                Text("Connected")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.green)
            }
            Group {
                if let earbuds = model.earbuds {
                    EarbudsArrival(symbols: earbuds, battery: event.battery)
                } else {
                    HeadphonesArrival(symbol: model.symbol, battery: event.battery)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The case pops up under the notch and the buds jump out of it, one to each side.
private struct EarbudsArrival: View {
    let symbols: (left: String, right: String, chargingCase: String)
    let battery: BluetoothBattery?

    /// How far from the case each bud lands.
    private static let spread: CGFloat = 82

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var caseShown = false
    @State private var budsOut = false
    @State private var filled = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                bud(symbols.left, side: -1)
                Image(systemName: symbols.chargingCase)
                    .font(.system(size: 31))
                    .symbolEffect(.bounce, value: budsOut)
                    .scaleEffect(caseShown ? 1 : 0.4)
                    .opacity(caseShown ? 1 : 0)
                    .blur(radius: caseShown ? 0 : 3)
                // Behind the case too, so both come out from inside it.
                bud(symbols.right, side: 1)
                    .zIndex(-1)
            }
            .frame(height: 38)
            ZStack {
                BatteryLevel(level: battery?.left, isKnown: battery != nil, isFilled: filled)
                    .offset(x: -Self.spread)
                BatteryLevel(level: battery?.caseLevel, isKnown: battery != nil, isFilled: filled, delay: 0.08)
                BatteryLevel(level: battery?.right, isKnown: battery != nil, isFilled: filled, delay: 0.16)
                    .offset(x: Self.spread)
            }
        }
        .task {
            if reduceMotion {
                caseShown = true
                filled = true
                return
            }
            // The notch is still growing: start once there's room.
            try? await Task.sleep(for: .seconds(0.1))
            withAnimation(.spring(duration: 0.45, bounce: 0.35)) { caseShown = true }
            try? await Task.sleep(for: .seconds(0.3))
            budsOut = true
            try? await Task.sleep(for: .seconds(0.55))
            filled = true
        }
    }

    /// A bud that springs up out of the case, leaning out, and drops into place beside it.
    private func bud(_ symbol: String, side: CGFloat) -> some View {
        let spread = Self.spread
        return Image(systemName: symbol)
            .font(.system(size: 27))
            .keyframeAnimator(initialValue: reduceMotion ? BudFlight.landed : .inCase, trigger: budsOut) { content, flight in
                content
                    .rotationEffect(.degrees(flight.tilt * side))
                    .scaleEffect(flight.scale)
                    .offset(x: flight.travel * spread * side, y: flight.lift)
                    .opacity(flight.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.travel) {
                    SpringKeyframe(1, duration: 0.6, spring: Spring(duration: 0.55, bounce: 0.12))
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-14, duration: 0.2)
                    SpringKeyframe(0, duration: 0.55, spring: Spring(duration: 0.45, bounce: 0.35))
                }
                KeyframeTrack(\.tilt) {
                    CubicKeyframe(30, duration: 0.2)
                    SpringKeyframe(0, duration: 0.7, spring: Spring(duration: 0.55, bounce: 0.45))
                }
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1, duration: 0.5, spring: Spring(duration: 0.4, bounce: 0.3))
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.12)
                }
            }
    }
}

nonisolated private struct BudFlight {
    /// 0 inside the case, 1 in its place beside it.
    var travel: CGFloat
    var lift: CGFloat = 0
    /// Degrees it leans out, away from the case.
    var tilt: Double = 0
    var scale: CGFloat
    var opacity: Double

    static let inCase = BudFlight(travel: 0, scale: 0.5, opacity: 0)
    static let landed = BudFlight(travel: 1, scale: 1, opacity: 1)
}

/// AirPods Max come down out of the notch turning like on a turntable, settle facing you and
/// send out a few sound waves.
private struct HeadphonesArrival: View {
    let symbol: String
    let battery: BluetoothBattery?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false
    @State private var wavesShown = false
    @State private var wavePulses = 0
    @State private var filled = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                wave("wave.3.left", side: -1)
                Image(systemName: symbol)
                    .font(.system(size: 36))
                    .keyframeAnimator(initialValue: reduceMotion ? Turn.facing : .away, trigger: turned) { content, turn in
                        content
                            .rotation3DEffect(.degrees(turn.angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                            .scaleEffect(turn.scale)
                            .offset(y: turn.drop)
                            .opacity(turn.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.angle) {
                            SpringKeyframe(0, duration: 1.3, spring: Spring(duration: 1.15, bounce: 0.18))
                        }
                        KeyframeTrack(\.drop) {
                            SpringKeyframe(0, duration: 0.6, spring: Spring(duration: 0.5, bounce: 0.3))
                        }
                        KeyframeTrack(\.scale) {
                            SpringKeyframe(1, duration: 0.6, spring: Spring(duration: 0.5, bounce: 0.3))
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 0.15)
                        }
                    }
                wave("wave.3.right", side: 1)
            }
            .frame(height: 38)
            BatteryLevel(level: battery?.main ?? battery?.summary, isKnown: battery != nil, isFilled: filled)
        }
        .task {
            if reduceMotion {
                filled = true
                return
            }
            try? await Task.sleep(for: .seconds(0.1))
            turned = true
            // Sound comes out as they settle.
            try? await Task.sleep(for: .seconds(0.65))
            withAnimation(.smooth(duration: 0.35)) { wavesShown = true }
            wavePulses += 1
            try? await Task.sleep(for: .seconds(0.2))
            filled = true
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.smooth(duration: 0.6)) { wavesShown = false }
        }
    }

    private func wave(_ symbol: String, side: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeat(3), value: wavePulses)
            .offset(x: wavesShown ? 0 : -6 * side)
            .opacity(wavesShown ? 1 : 0)
    }
}

nonisolated private struct Turn {
    var angle: Double
    var drop: CGFloat
    var scale: CGFloat
    var opacity: Double

    /// Up in the notch, edge-on, three quarters of a turn from facing.
    static let away = Turn(angle: -270, drop: -16, scale: 0.55, opacity: 0)
    static let facing = Turn(angle: 0, drop: 0, scale: 1, opacity: 1)
}

/// A ring under a bud, the case or the headphones that fills to its battery level once they've
/// landed. Empty while the level isn't known yet; gone for a part that doesn't report one (often
/// the case, once both buds are out of it).
private struct BatteryLevel: View {
    let level: Int?
    /// Whether the AirPods' battery came in at all.
    let isKnown: Bool
    let isFilled: Bool
    var delay: Double = 0

    var body: some View {
        let shown = isFilled ? level : nil
        HStack(spacing: 4) {
            ProgressRing(
                progress: Double(shown ?? 0) / 100,
                color: (shown ?? 100) <= 20 ? .orange : .green,
                lineWidth: 2,
                animation: .easeOut(duration: 0.9).delay(delay)
            )
            .frame(width: 12, height: 12)
            if let shown {
                Text("\(shown)%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(shown)))
                    .transition(.blurReplace)
            }
        }
        .opacity(isKnown && level == nil ? 0 : 1)
        .animation(.smooth(duration: 0.4).delay(delay), value: shown)
        .animation(.smooth(duration: 0.3), value: isKnown)
    }
}
