import Foundation
import Observation
import AppKit
import SwiftUI

struct FocusEvent: Equatable {
    var name: String
    var symbol: String
    var color: Color
    var isOn: Bool
    /// Focus changed, but macOS won't let DyNotch read to what (no Full Disk Access).
    var needsAccess = false

    /// Width of each wing that fits the name beside the notch (icon, name, margins), up to a cap.
    var wing: CGFloat {
        let text = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width
        return min(max(110, (text + 10 + 13 + 6 + 12).rounded(.up)), 200)
    }

    static let unreadable = FocusEvent(name: String(localized: "Focus"), symbol: "moon.fill", color: .indigo, isOn: false, needsAccess: true)
}

/// Watches the Focus (Do Not Disturb) database. There is no public API for this, so it
/// reads `~/Library/DoNotDisturb/DB`, which requires Full Disk Access. Best effort:
/// manual Focus changes are reliable, some automatic schedules may not be recorded there.
@Observable
final class FocusMonitor {
    private(set) var current: FocusEvent?

    @ObservationIgnored private weak var services: AppServices?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastModified: Date?
    @ObservationIgnored private var hasLoaded = false

    private static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
    }
    private static var assertionsURL: URL { directory.appendingPathComponent("Assertions.json") }
    private static var modesURL: URL { directory.appendingPathComponent("ModeConfigurations.json") }

    /// Whether DyNotch can read the Focus database (Full Disk Access granted).
    static var hasAccess: Bool {
        (try? FileHandle(forReadingFrom: assertionsURL))?.closeFile() != nil
    }

    /// The Focus database is there but can't be read: no Full Disk Access, or a stale one.
    static var isBlocked: Bool {
        FileManager.default.fileExists(atPath: assertionsURL.path) && !hasAccess
    }

    func start(services: AppServices) {
        self.services = services
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func poll() {
        guard let services, services.settings.liveFocus else { return }
        // The modification date is readable without Full Disk Access, the contents aren't.
        let modified = (try? FileManager.default.attributesOfItem(atPath: Self.assertionsURL.path))?[.modificationDate] as? Date
        guard modified != lastModified else { return }
        lastModified = modified
        defer { hasLoaded = true }

        guard let assertions = try? Data(contentsOf: Self.assertionsURL) else {
            // Rather than staying silent, say that a Focus change can't be shown.
            current = nil
            if hasLoaded {
                services.activities.post(LiveActivity(id: "focus", kind: .focus(.unreadable), duration: 2.5))
            }
            return
        }
        let focus = Self.activeFocus(assertions: assertions, modes: try? Data(contentsOf: Self.modesURL))
        let previous = current
        current = focus
        guard hasLoaded, focus?.name != previous?.name else { return }

        let event = focus ?? previous.map { FocusEvent(name: $0.name, symbol: $0.symbol, color: $0.color, isOn: false) }
        if let event {
            services.activities.post(LiveActivity(id: "focus", kind: .focus(event), duration: 2.5))
        }
    }

    /// The Focus that `Assertions.json` says is on, named from `ModeConfigurations.json`.
    static func activeFocus(assertions: Data, modes: Data?) -> FocusEvent? {
        // Only `storeAssertionRecords` are live: the file also keeps the assertions that
        // ended (invalidation records), and those name a mode too.
        guard let json = try? JSONSerialization.jsonObject(with: assertions),
              let identifier = findValues(forKey: "storeAssertionRecords", in: json)
                  .flatMap({ findValues(forKey: "assertionDetailsModeIdentifier", in: $0) })
                  .compactMap({ $0 as? String })
                  .last
        else { return nil }

        var name = String(localized: "Focus")
        var symbol = "moon.fill"
        var color = Color.indigo
        if let modes,
           let modesJSON = try? JSONSerialization.jsonObject(with: modes),
           let mode = findMode(identifier, in: modesJSON) {
            name = builtInName(identifier) ?? mode["name"] as? String ?? name
            symbol = mode["symbolImageName"] as? String ?? symbol
            color = tint(mode["tintColorName"] as? String) ?? color
            if let style = builtInStyle(identifier) { (symbol, color) = style }
        } else if let builtIn = builtInName(identifier) {
            name = builtIn
            if let style = builtInStyle(identifier) { (symbol, color) = style }
        } else if identifier == "com.apple.sleep.sleep-mode" {
            (name, symbol, color) = (String(localized: "Sleep", comment: "The Sleep Focus"), "bed.double.fill", .teal)
        } else if identifier.hasSuffix(".default") {
            name = String(localized: "Do Not Disturb")
        }
        return FocusEvent(name: name, symbol: symbol, color: color, isOn: true)
    }

    /// Apple's icon and colour for its own Focus modes.
    static func builtInStyle(_ identifier: String) -> (String, Color)? {
        switch identifier {
        case "com.apple.donotdisturb.mode.default": ("moon.fill", Color(red: 0.39, green: 0.36, blue: 0.96))
        case "com.apple.sleep.sleep-mode": ("bed.double.fill", Color(red: 0.39, green: 0.36, blue: 0.96))
        case "com.apple.focus.work": ("person.text.rectangle.fill", Color(red: 0.10, green: 0.78, blue: 0.80))
        case "com.apple.focus.personal-time": ("person.fill", Color(red: 0.80, green: 0.25, blue: 0.90))
        case "com.apple.donotdisturb.mode.driving": ("car.fill", Color(red: 0.39, green: 0.36, blue: 0.96))
        case "com.apple.focus.fitness": ("figure.run", Color(red: 0.20, green: 0.78, blue: 0.35))
        case "com.apple.focus.gaming": ("gamecontroller.fill", Color(red: 0.0, green: 0.48, blue: 1.0))
        case "com.apple.focus.mindfulness": ("camera.macro", Color(red: 0.10, green: 0.78, blue: 0.70))
        case "com.apple.focus.reading": ("book.closed.fill", Color(red: 1.0, green: 0.58, blue: 0.20))
        case "com.apple.focus.reduce-interruptions": ("atom", Color(red: 0.80, green: 0.25, blue: 0.90))
        default: nil
        }
    }

    /// The localized name of Apple's own Focus modes: the configuration file stores them in English.
    static func builtInName(_ identifier: String) -> String? {
        switch identifier {
        case "com.apple.donotdisturb.mode.default": String(localized: "Do Not Disturb")
        case "com.apple.sleep.sleep-mode": String(localized: "Sleep", comment: "The Sleep Focus")
        case "com.apple.focus.work": String(localized: "Work", comment: "The Work Focus")
        case "com.apple.focus.personal-time": String(localized: "Personal", comment: "The Personal Focus")
        case "com.apple.donotdisturb.mode.driving": String(localized: "Driving", comment: "The Driving Focus")
        case "com.apple.focus.fitness": String(localized: "Fitness", comment: "The Fitness Focus")
        case "com.apple.focus.gaming": String(localized: "Gaming", comment: "The Gaming Focus")
        case "com.apple.focus.mindfulness": String(localized: "Mindfulness", comment: "The Mindfulness Focus")
        case "com.apple.focus.reading": String(localized: "Reading", comment: "The Reading Focus")
        case "com.apple.focus.reduce-interruptions": String(localized: "Reduce Interruptions", comment: "The Reduce Interruptions Focus")
        default: nil
        }
    }

    /// Recursively collects the values for `key` anywhere in a JSON tree.
    static func findValues(forKey key: String, in json: Any) -> [Any] {
        if let dictionary = json as? [String: Any] {
            return dictionary.flatMap { entry -> [Any] in
                entry.key == key ? [entry.value] : findValues(forKey: key, in: entry.value)
            }
        }
        if let array = json as? [Any] {
            return array.flatMap { findValues(forKey: key, in: $0) }
        }
        return []
    }

    /// Finds the `mode` dictionary whose `modeIdentifier` matches.
    private static func findMode(_ identifier: String, in json: Any) -> [String: Any]? {
        if let dictionary = json as? [String: Any] {
            if dictionary["modeIdentifier"] as? String == identifier { return dictionary }
            for value in dictionary.values {
                if let found = findMode(identifier, in: value) { return found }
            }
        } else if let array = json as? [Any] {
            for value in array {
                if let found = findMode(identifier, in: value) { return found }
            }
        }
        return nil
    }

    private static func tint(_ name: String?) -> Color? {
        switch name {
        case "systemIndigoColor": .indigo
        case "systemPurpleColor": .purple
        case "systemBlueColor": .blue
        case "systemTealColor": .teal
        case "systemCyanColor": .cyan
        case "systemMintColor": .mint
        case "systemGreenColor": .green
        case "systemYellowColor": .yellow
        case "systemOrangeColor": .orange
        case "systemRedColor": .red
        case "systemPinkColor": .pink
        case "systemBrownColor": .brown
        case "systemGrayColor": .gray
        default: nil
        }
    }
}
