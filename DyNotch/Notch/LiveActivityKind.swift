import Foundation

/// Every kind of transient event the notch can show.
enum LiveActivityKind: Equatable {
    case hud(HUDSnapshot)
    case capsLock(Bool)
    case nowPlaying(title: String, artist: String, change: TrackChange)
    case meeting(MeetingEvent)
    case focus(FocusEvent)
    case timerFinished(TimerFinishedEvent)
    case battery(BatteryEvent)
    case bluetooth(BluetoothEvent)

    var priority: Int {
        switch self {
        case .hud: 100
        case .capsLock: 40
        case .nowPlaying: 10
        case .meeting: 80
        case .focus: 50
        case .timerFinished: 90
        case .battery(let event): event.kind == .low ? 70 : 60
        case .bluetooth: 55
        }
    }

    /// Whether a preempted activity should come back after the interrupting one.
    var requeueWhenPreempted: Bool {
        switch self {
        case .meeting, .timerFinished: true
        case .hud, .capsLock, .nowPlaying, .focus, .battery, .bluetooth: false
        }
    }

    /// The tab with more about it, while it's in the tab bar: where the notch opens while it shows.
    func tab(in settings: AppSettings) -> NotchTab? {
        switch self {
        case .timerFinished: settings.tab(about: .timer, ownTab: .timers)
        case .nowPlaying: settings.tab(about: .media)
        case .meeting: settings.tab(about: .calendar)
        case .battery: settings.tab(about: .battery)
        case .hud, .capsLock, .focus, .bluetooth: nil
        }
    }

    func layout(notch: CGSize) -> ActivityLayout {
        switch self {
        case .hud(let snapshot): .expanded(width: max(notch.width + 140, 330), extraHeight: snapshot.caption == nil ? 30 : 48)
        case .capsLock: .wings(92)
        case .focus: .wings(110)
        case .timerFinished: .expanded(width: max(notch.width + 200, 420), extraHeight: 50)
        case .battery: .wings(108)
        case .bluetooth(let event):
            // AirPods connecting drop down to play themselves in; anything else fits beside the notch.
            event.animatedAirPods != nil
                ? .expanded(width: max(notch.width + 236, 420), extraHeight: 74)
                : .wings(140)
        case .nowPlaying(_, _, let change):
            // A song that played out keeps the size of the album art beside the notch.
            // A skip drops down far enough for the title and artist to sit under the notch, beside the cover.
            change == .continued
                ? .wings(CompactActivity.media.wing)
                : .expanded(width: max(notch.width + 200, 400), extraHeight: 52)
        case .meeting: .expanded(width: max(notch.width + 200, 420), extraHeight: 50)
        }
    }
}
