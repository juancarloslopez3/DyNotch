import SwiftUI

@main
struct DyNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra("DyNotch", systemImage: "capsule.tophalf.filled", isInserted: $settings.showMenuBarIcon) {
            MenuBarContent()
        }
    }
}

private struct MenuBarContent: View {
    var body: some View {
        Button("Open Notch") {
            AppServices.shared.notch.openPrimary()
        }
        Divider()
        Button("Settings…") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",")
        Button("Permissions…") {
            SettingsWindowController.shared.show(pane: .permissions)
        }
        Button("Welcome Tour…") {
            OnboardingWindowController.shared.show(step: .welcome)
        }
        Divider()
        Button("Quit DyNotch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
