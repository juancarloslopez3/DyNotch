import SwiftUI

/// Volume / brightness / backlight HUD: icon and percentage beside the notch, a draggable
/// glass level bar below it, and above the bar the display it's about when that isn't plain.
struct HUDView: View {
    @Environment(AppServices.self) private var services
    let snapshot: HUDSnapshot
    let notch: CGSize

    var body: some View {
        VStack(spacing: 0) {
            WingsLayout(notch: notch) {
                Image(systemName: snapshot.symbol, variableValue: Double(snapshot.displayLevel))
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 22)
            } trailing: {
                Text(snapshot.isUnavailable ? "—" : "\(Int((snapshot.displayLevel * 100).rounded()))")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(snapshot.displayLevel)))
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
                .padding(.horizontal, 22)
                .frame(maxHeight: .infinity)
            }
        }
        .animation(.notchQuick, value: snapshot)
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
