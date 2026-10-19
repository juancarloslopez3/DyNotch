import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Bindable var selection: SettingsSelection

    var body: some View {
        NavigationSplitView {
            List(selection: $selection.pane) {
                ForEach(SettingsPane.groups, id: \.self) { group in
                    Section {
                        ForEach(group) { pane in
                            Label {
                                Text(pane.title)
                            } icon: {
                                Image(systemName: pane.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(pane.color.gradient, in: .rect(cornerRadius: 5))
                            }
                            .tag(pane)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        } detail: {
            Group {
                switch selection.pane {
                case .general: GeneralPane()
                case .layout: LayoutPane()
                case .nowPlaying: NowPlayingPane()
                case .clock: ClockPane()
                case .weather: WeatherPane()
                case .calendar: CalendarPane()
                case .timers: TimersPane()
                case .camera: CameraPane()
                case .live: LiveActivitiesPane()
                case .hud: HUDPane()
                case .permissions: PermissionsPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(selection.pane.title)
            // Permissions change in System Settings, so the notices under the settings that
            // need one are brought up to date whenever a pane shows or DyNotch comes back.
            .onChange(of: selection.pane, initial: true) { services.permissions.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                services.permissions.refresh()
            }
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Environment(AppServices.self) private var services
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var language = AppLanguage.chosen

    var body: some View {
        @Bindable var settings = services.settings
        Form {
            Section("Opening") {
                Picker("Open the notch by", selection: $settings.openMode) {
                    ForEach(OpenMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if settings.openMode == .hover {
                    LabeledContent("Hover delay") {
                        HStack {
                            Slider(value: $settings.hoverDelay, in: 0...0.8, step: 0.05)
                                .frame(maxWidth: 220)
                            Text("\(settings.hoverDelay, format: .number.precision(.fractionLength(2))) s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                } else {
                    Text("Hovering shows a small peek; click the notch to open it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Toggle(isOn: $settings.swipeToOpen) {
                    Text("Swipe down to open, up to close")
                    Text("With two fingers over the notch.")
                }
                .onChange(of: settings.swipeToOpen) { services.notch.swipes.update() }
                Toggle("Haptic feedback on the trackpad", isOn: $settings.hapticsEnabled)
            }
            Section("Displays") {
                Toggle("Show a notch on external displays", isOn: $settings.showOnExternalDisplays)
                    .onChange(of: settings.showOnExternalDisplays) { services.notch.rebuild() }
                Toggle(isOn: $settings.hideInFullScreen) {
                    Text("Hide in full-screen apps")
                    Text("Volume and brightness HUDs still appear.")
                }
            }
            Section("App") {
                Picker("Language", selection: $language) {
                    Text(AppLanguage.system.title).tag(AppLanguage.system)
                    Divider()
                    ForEach([AppLanguage.english, .spanish]) { Text($0.title).tag($0) }
                }
                .onChange(of: language) { AppLanguage.choose(language) }
                // macOS picks the language as DyNotch launches.
                if language.resolved != AppLanguage.running {
                    LabeledContent {
                        Button("Restart Now", action: AppLanguage.relaunch)
                    } label: {
                        Text("Restart DyNotch to change the language")
                        Text("It opens again right away, with Settings where you left it.")
                    }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle(isOn: $settings.showMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text("Without it, open DyNotch again from Finder or Spotlight to get back to Settings.")
                }
                // DyNotch has no app menu, so with the menu bar icon hidden this is the only Quit.
                LabeledContent {
                    Button("Quit DyNotch") { NSApp.terminate(nil) }
                } label: {
                    Text("Quit")
                    Text("The notch goes back to normal until you open DyNotch again.")
                }
            }
        }
    }
}

// MARK: - Live Activities

private struct LiveActivitiesPane: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var settings = services.settings
        Form {
            Section {
                Toggle("A charger is plugged in or the battery runs low", isOn: $settings.liveBattery)
                Toggle("A Bluetooth device connects", isOn: $settings.liveBluetooth)
                if settings.liveBluetooth {
                    Toggle("Animate AirPods as they connect", isOn: $settings.liveAirPodsAnimation)
                        .padding(.leading, 18)
                    PermissionNotice(.bluetooth, "Needs Bluetooth to see devices connect.")
                }
                Toggle("Caps Lock is toggled", isOn: $settings.liveCapsLock)
                if settings.liveCapsLock {
                    Toggle("Keep an indicator while Caps Lock is on", isOn: $settings.capsLockPersistent)
                        .padding(.leading, 18)
                    PermissionNotice(.accessibility, "Needs Accessibility to see Caps Lock.")
                }
            } header: {
                Text("Show in the Notch When")
            } footer: {
                Text("Song changes and online meetings are in Now Playing and Calendar & Reminders.")
            }
            Section {
                Toggle("A Focus mode turns on or off", isOn: $settings.liveFocus)
                if settings.liveFocus {
                    PermissionNotice(.fullDiskAccess, "Needs Full Disk Access to read Focus status.")
                }
            } header: {
                Text("Focus")
            } footer: {
                Text("macOS has no public API for Focus. DyNotch reads the Focus database, which may miss some automatic schedules.")
            }
        }
    }
}

// MARK: - Volume & Brightness

private struct HUDPane: View {
    @Environment(AppServices.self) private var services
    @State private var keyboardLevel: Float = 0

    var body: some View {
        @Bindable var settings = services.settings
        let hud = services.hud
        Form {
            Section {
                Toggle("Volume", isOn: $settings.hudVolume)
                Toggle("Display brightness", isOn: $settings.hudBrightness)
                Toggle("Keyboard backlight", isOn: $settings.hudKeyboard)
                PermissionNotice(.accessibility, "Needs Accessibility to replace the system HUD.")
            } header: {
                Text("Replace the System HUD For")
            } footer: {
                Text("Hold ⇧⌥ while pressing the keys for finer steps.")
            }
            Section {
                Picker("Brightness keys adjust", selection: $settings.brightnessKeyScope) {
                    ForEach(BrightnessKeyScope.allCases) { Text($0.title).tag($0) }
                }
                ForEach(hud.displays.connected) { display in
                    DisplayBrightnessRow(display: display)
                }
            } header: {
                Text("Displays")
            } footer: {
                Text("Displays not made by Apple are adjusted over DDC/CI. If one doesn't respond, turn on DDC/CI in its own menu; some docks and adapters don't pass it on.")
            }
            Section {
                Picker("Adjust with the brightness keys while holding", selection: $settings.backlightModifier) {
                    ForEach(BacklightModifier.allCases) { Text($0.title).tag($0) }
                }
                if hud.keyboard.isAvailable {
                    LabeledContent("Brightness") {
                        Slider(value: $keyboardLevel, in: 0...1) { _ in }
                            .frame(maxWidth: 240)
                            .onChange(of: keyboardLevel) { _, level in
                                hud.set(.keyboard, level: level, showHUD: false)
                            }
                    }
                }
            } header: {
                Text("Keyboard Backlight")
            } footer: {
                Text("MacBooks with Touch ID have no backlight keys. Hold the modifier and press the brightness keys instead, or use the slider.")
            }
        }
        .onAppear {
            keyboardLevel = hud.keyboard.brightness() ?? 0
            hud.displays.refresh()
        }
    }
}

/// A display's brightness, and how DyNotch reaches it.
private struct DisplayBrightnessRow: View {
    @Environment(AppServices.self) private var services
    let display: BrightnessDisplay

    var body: some View {
        if display.isAdjustable {
            LabeledContent {
                Slider(value: level, in: 0...1)
                    .frame(maxWidth: 240)
            } label: {
                Text(display.name)
                if display.control == .ddc {
                    Text(display.answered == false ? "Didn't answer over DDC/CI" : "Over DDC/CI")
                }
            }
        } else {
            LabeledContent(display.name) {
                Text("Can't be adjusted")
            }
        }
    }

    private var level: Binding<Float> {
        Binding {
            display.level ?? 0.5
        } set: { level in
            services.hud.displays.setLevel(level, of: display.id)
        }
    }
}

// MARK: - Permissions

private struct PermissionsPane: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    AllowAllButton(isProminent: false) { SettingsWindowController.shared.show() }
                } label: {
                    Text(services.permissions.allGranted ? "Everything is allowed" : "Allow everything DyNotch can use")
                    Text("Asks for each one in turn: answer the prompts, then switch on the rest in System Settings.")
                }
            }
            Section {
                PermissionsList()
            } footer: {
                Text("DyNotch keeps everything on your Mac. Weather requests send only coordinates to Open-Meteo.")
            }
        }
    }
}

// MARK: - About

private enum UpdateStatus: Equatable {
    case idle, checking, upToDate, failed
    case available(UpdateChecker.Release)
}

private struct AboutPane: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    @State private var update = UpdateStatus.idle

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DyNotch").font(.title2.bold())
                        Text("Version \(version)")
                            .foregroundStyle(.secondary)
                        Text("A Dynamic Island for your Mac's notch.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            Section {
                LabeledContent {
                    switch update {
                    case .checking:
                        ProgressView()
                            .controlSize(.small)
                    case .available(let release):
                        HStack {
                            Button("Release Notes") { NSWorkspace.shared.open(release.page) }
                            Button("Download") { NSWorkspace.shared.open(release.download) }
                                .buttonStyle(.borderedProminent)
                        }
                    case .failed:
                        Button("Try Again", action: checkForUpdates)
                    case .idle, .upToDate:
                        Button("Check for Updates", action: checkForUpdates)
                    }
                } label: {
                    updateTitle
                    updateDetail
                }
                LabeledContent {
                    Button("Star on GitHub", systemImage: "star") { NSWorkspace.shared.open(UpdateChecker.repository) }
                } label: {
                    Text("Enjoying DyNotch?")
                    Text("It's open source. A star helps others find it.")
                }
                LabeledContent("New to DyNotch?") {
                    Button("Welcome Tour…") { OnboardingWindowController.shared.show(step: .welcome) }
                }
            }
            Section("Acknowledgements") {
                LabeledContent("mediaremote-adapter") {
                    Link("BSD 3-Clause · Jonas van den Berg", destination: URL(string: "https://github.com/ungive/mediaremote-adapter")!)
                }
                LabeledContent("Weather data") {
                    Link("Open-Meteo.com · CC BY 4.0", destination: URL(string: "https://open-meteo.com")!)
                }
            }
        }
    }

    private var updateTitle: Text {
        switch update {
        case .idle, .checking: Text("Updates")
        case .upToDate: Text("DyNotch is up to date")
        case .failed: Text("Couldn't check for updates")
        case .available(let release): Text("DyNotch \(release.version) is available")
        }
    }

    private var updateDetail: Text {
        switch update {
        case .idle, .checking: Text("Looks for a newer version on GitHub.")
        case .upToDate: Text("Version \(version) is the latest.")
        case .failed: Text("GitHub didn't answer. Check your internet connection and try again.")
        case .available: Text("You have version \(version).")
        }
    }

    private func checkForUpdates() {
        update = .checking
        Task {
            do {
                update = try await UpdateChecker.newerRelease(than: version).map(UpdateStatus.available) ?? .upToDate
            } catch {
                update = .failed
            }
        }
    }
}
