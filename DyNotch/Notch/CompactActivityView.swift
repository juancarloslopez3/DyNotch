import SwiftUI

/// Content beside the closed notch for persistent activities.
struct CompactActivityView: View {
    @Environment(AppServices.self) private var services
    let activity: CompactActivity
    let notch: CGSize
    var isHovering = false

    var body: some View {
        // The band beside the notch grows with the shape while hovered, so content stays centred in it.
        let band = CGSize(width: notch.width, height: notch.height + (isHovering ? NotchMetrics.compactHoverGrowth.height : 0))
        switch activity {
        case .media:
            CompactMediaView(notch: band, isHovering: isHovering)
        case .timer:
            CompactTimerView(notch: band)
        case .capsLock:
            WingsLayout(notch: band) {
                Image(systemName: "capslock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
            } trailing: {
                Circle().fill(.green).frame(width: 6, height: 6)
            }
        case .clock:
            WingsLayout(notch: band) {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } trailing: {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

/// A second activity going on, in its bubble beside the notch: just enough to tell it apart, like
/// the Dynamic Island's minimal views.
struct MinimalActivityView: View {
    let activity: CompactActivity
    let size: CGSize

    var body: some View {
        switch activity {
        case .media:
            let cover = (size.height * 0.7).rounded()
            CompactCoverView(size: cover, cornerRadius: cover / 2)
        case .timer:
            MinimalTimerView(height: size.height)
        case .capsLock:
            Image(systemName: "capslock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        case .clock:
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }
}

/// Content for transient live activities.
struct LiveActivityView: View {
    let activity: LiveActivity
    let notch: CGSize

    var body: some View {
        switch activity.kind {
        case .hud(let snapshot):
            HUDView(snapshot: snapshot, notch: notch)
        case .capsLock(let on):
            WingsLayout(notch: notch) {
                Image(systemName: on ? "capslock.fill" : "capslock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(on ? .green : .white.opacity(0.7))
            } trailing: {
                Text(on ? "Caps Lock" : "Caps Off")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? .white : .white.opacity(0.7))
            }
        case .nowPlaying(let title, let artist, let change):
            if case .skipped(let forward) = change {
                NowPlayingActivityView(title: title, artist: artist, forward: forward, notch: notch)
            } else {
                CompactMediaView(notch: notch)
            }
        case .meeting(let meeting):
            MeetingActivityView(meeting: meeting, notch: notch)
        case .battery(let event):
            BatteryActivityView(event: event, notch: notch)
        case .bluetooth(let event):
            if let model = event.animatedAirPods {
                AirPodsActivityView(event: event, model: model, notch: notch)
            } else {
                BluetoothActivityView(event: event, notch: notch)
            }
        case .timerFinished(let event):
            TimerFinishedView(event: event, notch: notch)
        case .focus(let focus):
            WingsLayout(notch: notch) {
                HStack(spacing: 6) {
                    Image(systemName: focus.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(focus.isOn ? focus.color : .white.opacity(0.5))
                    Text(focus.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
            } trailing: {
                Text(focus.needsAccess ? "Needs access" : focus.isOn ? "On" : "Off")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(focus.isOn ? focus.color : .white.opacity(0.6))
            }
        }
    }
}
