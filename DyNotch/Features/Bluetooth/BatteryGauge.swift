import SwiftUI

/// A connected device's battery beside the notch: the ring draws round to `level` while the
/// percentage comes out from it and counts up with it, orange when low. An empty ring until the
/// level is known.
struct BatteryGauge: View {
    let level: Int?
    var ring: CGFloat
    var spacing: CGFloat = 5

    /// The ring drawing round, and the percentage counting up with it.
    static let fill = Animation.easeOut(duration: 0.9)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filling = false
    /// The level the ring draws round to, set apart from `level`: a level that comes in late
    /// slides the ring over, and drawn in the same update the arc would slide with the draw's
    /// slow ease and trail its track.
    @State private var drawn: Int?

    var body: some View {
        let low = (level ?? 100) <= 20
        HStack(spacing: spacing) {
            ProgressRing(
                progress: Double(drawn ?? 0) / 100,
                color: low ? .orange : .green,
                lineWidth: 2.5,
                animation: Self.fill
            )
            .frame(width: ring, height: ring)
            if let level {
                CountingPercent(level: level, counting: filling)
                    .foregroundStyle(low ? .orange : .white)
                    .transition(.identity)
            }
        }
        // A level that comes in late slides the ring over to make room.
        .animation(.notchQuick, value: level)
        .onChange(of: filling) { draw() }
        .onChange(of: level) { draw() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(level ?? 0)%"))
        .accessibilityHidden(level == nil)
        .task {
            // The notch is still growing: start once there's room.
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(0.35))
            }
            filling = true
        }
    }

    private func draw() {
        if filling { drawn = level }
    }
}

/// The battery's percentage: once `counting`, it comes out from the ring and counts up as the ring
/// draws round. As wide as the end figure all along, so the ring beside it stays put.
private struct CountingPercent: View {
    let level: Int
    let counting: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var value: Double = 0
    @State private var showing = false

    var body: some View {
        Text("\(level)%")
            .hidden()
            .overlay(alignment: .leading) {
                Count(value: value)
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .opacity(showing ? 1 : 0)
            .blur(radius: showing ? 0 : 3)
            .offset(x: showing ? 0 : -6)
            .onChange(of: counting, initial: true) { count() }
            .onChange(of: level) { count() }
    }

    private func count() {
        guard counting else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { showing = true }
        withAnimation(reduceMotion ? nil : BatteryGauge.fill) { value = Double(level) }
    }
}

/// The whole percentage `value` is at, on every frame of an animation to it.
private struct Count: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))%")
    }
}
