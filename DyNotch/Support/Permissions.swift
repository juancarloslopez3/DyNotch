import AppKit
import ApplicationServices

enum Permissions {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Takes DyNotch off a privacy list in System Settings (`service` is the TCC service name, as
    /// `tccutil` takes it), switch and all.
    static func removeFromList(_ service: String) async {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, bundleID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume()
            }
        }
    }

    enum SettingsPane: String {
        case accessibility = "Privacy_Accessibility"
        case calendars = "Privacy_Calendars"
        case reminders = "Privacy_Reminders"
        case location = "Privacy_LocationServices"
        case camera = "Privacy_Camera"
        case bluetooth = "Privacy_Bluetooth"
        case systemAudio = "Privacy_AudioCapture"
        case fullDiskAccess = "Privacy_AllFiles"
        case notifications
    }

    static func openSystemSettings(_ pane: SettingsPane) {
        let url = switch pane {
        case .notifications:
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        default:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")!
        }
        NSWorkspace.shared.open(url)
    }
}
