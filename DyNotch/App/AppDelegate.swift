import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isRunningTests else { return }
        AppServices.shared.start()
        let settings = AppSettings.shared
        if let step = settings.tourStepToResume {
            // DyNotch quit with the tour open, as allowing Full Disk Access makes it: pick up there.
            OnboardingWindowController.shared.show(step: step)
        } else if !settings.hasCompletedOnboarding {
            OnboardingWindowController.shared.show(step: .welcome)
        } else if AppLanguage.isRelaunch {
            // Restarted from Settings › General to change the language.
            SettingsWindowController.shared.show(pane: .general)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppServices.shared.media.stop()
    }

    /// Re-launching the app (e.g. from Finder) while it runs opens Settings, since there
    /// is no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }
}
