#if DEBUG
import AppKit
import SwiftUI

/// Debug-only remote control so the notch can be driven from the terminal, e.g.
/// `swift scripts/notch.swift open timers`.
enum DebugCommands {
    static let notificationName = Notification.Name("app.dynotch.debug")
    private static var observer: NSObjectProtocol?

    static func start(services: AppServices) {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            let command = notification.object as? String ?? ""
            MainActor.assumeIsolated { run(command, services: services) }
        }
    }

    private static func run(_ command: String, services: AppServices) {
        let parts = command.split(separator: " ").map(String.init)
        guard let verb = parts.first else { return }
        let argument = parts.dropFirst().first
        switch verb {
        case "open":
            services.notch.openPrimary(tab: argument.flatMap(NotchTab.init(rawValue:)))
        case "close":
            services.notch.models.forEach { $0.close() }
        case "swipe":
            // `swipe` / `swipe back`, as swiping left or right over the open notch.
            services.notch.models.first(where: \.isOpen)?.swipeTab(by: argument == "back" ? -1 : 1)
        case "hud":
            let kind = argument.flatMap(HUDKind.init(rawValue:)) ?? .volume
            services.activities.post(LiveActivity(id: "hud", kind: .hud(services.hud.snapshot(for: kind)), duration: 4))
        case "caps":
            services.activities.post(LiveActivity(id: "capslock", kind: .capsLock(true), duration: 4))
        case "dismiss":
            services.activities.dismiss()
        case "timer":
            services.timers.startTimer(duration: TimeInterval(argument.flatMap(Int.init) ?? 90))
        case "canceltimer":
            services.timers.cancelTimer()
        case "drop":
            services.notch.primary?.isShowingDropTarget = argument != "off"
        case "battery":
            services.activities.post(LiveActivity(id: "battery", kind: .battery(BatteryEvent(
                kind: argument == "low" ? .low : .pluggedIn, percent: argument == "low" ? 9 : 64, isCharging: argument != "low", minutes: 48
            )), duration: 4))
        case "bt":
            // `bt` / `bt max` / `bt airpods` / `bt 4` connect AirPods, `bt mouse` anything else;
            // add `late` for a battery that comes in a moment after, `off` to disconnect.
            let model: AirPodsModel? = switch argument {
            case "max": .airPodsMax
            case "airpods": .airPods
            case "3": .airPods3
            case "4": .airPods4
            case "mouse": nil
            default: .airPodsPro
            }
            let battery = model == .airPodsMax ? BluetoothBattery(main: 72)
                : model == nil ? BluetoothBattery(main: 45)
                : BluetoothBattery(left: 84, right: 18, caseLevel: 60)
            let late = parts.contains("late")
            let event = BluetoothEvent(
                address: "demo", name: model.map { "My \($0.name)" } ?? "Magic Mouse",
                symbol: model?.symbol ?? "magicmouse.fill", isConnected: !parts.contains("off"),
                battery: late ? nil : battery, airPods: model,
                animatesAirPods: services.settings.liveAirPodsAnimation
            )
            services.activities.post(LiveActivity(id: "bt-demo", kind: .bluetooth(event), duration: model == nil ? 3.5 : 5))
            if late {
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    services.activities.update(id: "bt-demo") { activity in
                        if case .bluetooth(var updated) = activity.kind {
                            updated.battery = battery
                            activity.kind = .bluetooth(updated)
                        }
                    }
                }
            }
        case "focus":
            services.activities.post(LiveActivity(id: "focus", kind: .focus(FocusEvent(
                name: "Work", symbol: "briefcase.fill", color: .cyan, isOn: true
            )), duration: 4))
        case "meeting":
            services.activities.post(LiveActivity(id: "meeting-demo", kind: .meeting(MeetingEvent(
                title: "Design Review", start: .now.addingTimeInterval(240), url: URL(string: "https://zoom.us/j/123")!,
                service: "Zoom", color: .blue
            )), duration: 6))
        case "timerdone":
            services.activities.post(LiveActivity(id: "timer-done", kind: .timerFinished(TimerFinishedEvent(
                title: "Timer Done", detail: "5:00 timer", mode: .timer
            )), duration: 6))
        case "song":
            // `song` / `song back` for a skip, `song end` for a song that played out.
            let change: TrackChange = switch argument {
            case "end": .continued
            case "back": .skipped(forward: false)
            default: .skipped(forward: true)
            }
            services.activities.post(LiveActivity(
                id: "nowplaying", kind: .nowPlaying(title: "Midnight City", artist: "M83", change: change), duration: 4
            ))
        case "settings":
            SettingsWindowController.shared.show(pane: argument.flatMap(SettingsPane.init(rawValue:)))
        case "tour":
            // `tour` / `tour hud`: the welcome tour, at a step.
            OnboardingWindowController.shared.show(step: argument.flatMap { name in
                OnboardingStep.allCases.first { "\($0)" == name }
            } ?? .welcome)
        case "guide":
            // `guide accessibility`: System Settings with the guide under it, as Open Settings does.
            services.permissions.openSettings(argument.flatMap(PermissionKind.init(rawValue:)) ?? .accessibility)
        default:
            break
        }
    }
}
#endif
