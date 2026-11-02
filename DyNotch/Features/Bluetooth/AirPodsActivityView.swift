import SwiftUI

/// AirPods and Beats connecting: they turn into view beside the notch as on the iPhone, by a ring
/// that fills to their battery and its percentage. As Apple pictures them (`DeviceArt`): a model
/// seen for the first time shows once Apple's clip of it is in.
struct AirPodsActivityView: View {
    let event: BluetoothEvent
    let model: AirPodsModel
    let notch: CGSize

    /// Width each wing adds beside the notch for AirPods that turn in there: room for the ring and
    /// "100%" on the right.
    static let wing: CGFloat = 68
    /// Width the AirPods turn in, in the left wing.
    static let pictureWidth: CGFloat = 38

    var body: some View {
        let productID = event.productID ?? model.typicalProductID
        TurningAirPods(
            name: event.name,
            symbol: model.symbol,
            turntable: DeviceArt.shared.turntable(productID: productID, colorID: event.colorID)
                ?? model.turntable(productID: productID, colorID: event.colorID).flatMap(Turntable.named),
            render: ProductRender.image(productID: productID, colorID: event.colorID),
            level: event.battery?.summary,
            notch: notch
        )
    }
}

/// The iPhone's AirPods connecting: they spin into view in the left wing, a whole turn like on a
/// turntable, while the ring in the right one draws round to their battery (the lower bud's),
/// its percentage beside it.
/// Turned in 3D as Apple's video of them turns, or where the app has a model of them; in their
/// color, where it's known. Without either (yet), as macOS pictures them or as their symbol, still:
/// a flat picture turned round looks like a card, not them.
private struct TurningAirPods: View {
    let name: String
    let symbol: String
    let turntable: Turntable?
    let render: NSImage?
    let level: Int?
    let notch: CGSize

    /// Nearly all of the 5 seconds the AirPods show for (`BluetoothMonitor`).
    private static let turnDuration = 4.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    var body: some View {
        let ring = (notch.height * 0.56).rounded()
        WingsLayout(notch: notch) {
            KeyframeAnimator(initialValue: reduceMotion ? Turn.facing : .away, trigger: turned) { turn in
                picture(at: turn.angle)
                    .scaleEffect(turn.scale)
                    .opacity(turn.opacity)
            } keyframes: { _ in
                // Slowly, for as long as they show, easing into facing just before the notch closes.
                KeyframeTrack(\.angle) {
                    LinearKeyframe(0, duration: Self.turnDuration, timingCurve: .bezier(startControlPoint: UnitPoint(x: 0.3, y: 0.3), endControlPoint: UnitPoint(x: 0.55, y: 1)))
                }
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1, duration: 0.6, spring: Spring(duration: 0.5, bounce: 0.3))
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.15)
                }
            }
        } trailing: {
            BatteryGauge(level: level, ring: ring)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(level.map { Text("\($0)%") } ?? Text("Connected"))
        .task {
            guard !reduceMotion else { return }
            // The notch is still growing: start once there's room.
            try? await Task.sleep(for: .seconds(0.1))
            turned = true
        }
    }

    /// Them `angle` degrees round.
    private func picture(at angle: Double) -> some View {
        let side = notch.height - 4
        return ZStack {
            if let turntable {
                turning(turntable, at: angle, height: side)
                    .id(ObjectIdentifier(turntable.frames[0]))
            } else if let render {
                Image(nsImage: render)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: (notch.height * 0.62).rounded()))
                    .foregroundStyle(.white)
            }
        }
        // Apple's model coming in while they show, when fetching it took longer than the wait
        // for it (`BluetoothMonitor`).
        .animation(.easeInOut(duration: 0.35), value: turntable.map { ObjectIdentifier($0.frames[0]) })
    }

    /// As big as fits in the wing all the way round, the frames either side of the angle blended so
    /// the slow turn doesn't step.
    private func turning(_ turntable: Turntable, at angle: Double, height: CGFloat) -> some View {
        let (first, second, fraction) = turntable.frames(around: angle)
        let room = CGSize(width: AirPodsActivityView.pictureWidth, height: height)
        let scale = min(room.width / turntable.size.width, room.height / turntable.size.height)
        return ZStack {
            Image(decorative: first, scale: 1)
                .resizable()
                .interpolation(.high)
                .opacity(1 - fraction)
            Image(decorative: second, scale: 1)
                .resizable()
                .interpolation(.high)
                .opacity(fraction)
                .blendMode(.plusLighter)
        }
        .compositingGroup()
        .frame(width: turntable.size.width * scale, height: turntable.size.height * scale)
    }
}

nonisolated private struct Turn {
    var angle: Double
    var scale: CGFloat
    var opacity: Double

    /// Small, a whole turn from facing.
    static let away = Turn(angle: -360, scale: 0.5, opacity: 0)
    static let facing = Turn(angle: 0, scale: 1, opacity: 1)
}
