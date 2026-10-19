import AppKit

/// The language DyNotch shows itself in. Default follows macOS: the system's languages, or the
/// one picked for DyNotch in System Settings › General › Language & Region › Applications,
/// which saves the same `AppleLanguages` key in DyNotch's defaults as choosing one here does.
/// macOS reads it at launch, so a new choice shows once DyNotch opens again.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", spanish = "es"

    var id: String { rawValue }

    /// Each language is named in itself, so it can be found whichever one shows now.
    var title: String {
        switch self {
        case .system: String(localized: "Default (\(Self.name(of: Self.systemLanguage)))", comment: "The macOS language, e.g. Default (English)")
        case .english: Self.name(of: rawValue)
        case .spanish: Self.name(of: rawValue)
        }
    }

    /// What's saved for the next launch.
    static var chosen: AppLanguage {
        guard let preferred = (appDefaults?["AppleLanguages"] as? [String])?.first else { return .system }
        let code = Locale(identifier: preferred).language.languageCode?.identifier
        return allCases.first { $0 != .system && $0.rawValue == code } ?? .system
    }

    /// The language DyNotch shows now: "en" or "es".
    static var running: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// The language DyNotch will show with this choice.
    var resolved: String { self == .system ? Self.systemLanguage : rawValue }

    /// Saves the choice for the next launch. A chosen language goes with the region macOS is
    /// set to, so dates read in the same language as the rest (macOS would otherwise write them
    /// in the system's language) while times and units stay as the region has them.
    static func choose(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        if language == .system {
            defaults.removeObject(forKey: "AppleLanguages")
            defaults.removeObject(forKey: "AppleLocale")
        } else {
            let region = (globalDefaults?["AppleLocale"] as? String).flatMap { Locale(identifier: $0).region?.identifier }
            defaults.set([language.rawValue], forKey: "AppleLanguages")
            defaults.set(region.map { "\(language.rawValue)_\($0)" } ?? language.rawValue, forKey: "AppleLocale")
        }
    }

    /// Quits and opens DyNotch again once this one has gone, with Settings back on screen.
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$0" --args -reopenSettings YES"#,
            Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier),
        ]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }

    /// Whether this launch is `relaunch()` opening DyNotch again.
    static var isRelaunch: Bool { UserDefaults.standard.bool(forKey: "reopenSettings") }

    /// The language macOS would pick for DyNotch, of the ones it has.
    private static var systemLanguage: String {
        let preferred = globalDefaults?["AppleLanguages"] as? [String] ?? []
        return Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: preferred).first ?? "en"
    }

    private static func name(of code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }

    /// DyNotch's own defaults, without the system-wide ones `UserDefaults.standard` falls back to.
    private static var appDefaults: [String: Any]? {
        Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:))
    }

    private static var globalDefaults: [String: Any]? {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
    }
}
