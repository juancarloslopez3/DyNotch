import AppKit
import SwiftUI

// The panes for what the notch shows, each with everything about its feature: what it shows
// in the notch and beside it, and the permission it needs.

// MARK: - Now Playing

struct NowPlayingPane: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var settings = services.settings
        Form {
            Section("Beside the Notch") {
                Toggle("Show music while it plays", isOn: $settings.showCompactMedia)
                Toggle(isOn: $settings.barsFollowMusic) {
                    Text("Bars move with the music")
                    Text("Like the iPhone's Dynamic Island. Nothing is recorded, but macOS shows its purple dot while the bars listen.")
                }
                .onChange(of: settings.barsFollowMusic) { services.media.updateMeter() }
                if settings.barsFollowMusic {
                    PermissionNotice(.systemAudio, "Needs System Audio Recording; until then the bars keep a steady rhythm.")
                }
                Toggle(isOn: $settings.liveSongChange) {
                    Text("Show the next song when it changes")
                    Text("Skipping drops down its cover, title and artist.")
                }
                // Hiding the whole notch in full-screen apps hides the player too.
                Toggle(isOn: settings.hideInFullScreen ? .constant(true) : $settings.hidePlayerInFullScreen) {
                    Text("Hide during full-screen videos")
                    Text(settings.hideInFullScreen
                        ? "Already hidden: DyNotch hides in every full-screen app (General › Displays)."
                        : "Folds away 3 seconds after the video that's playing fills the screen, like YouTube in full screen. A browser window in full screen keeps it.")
                }
                .disabled(settings.hideInFullScreen)
            }
            Section("Player") {
                Toggle("Tint the player with the album artwork's color", isOn: $settings.tintWithArtwork)
                Picker("When nothing is playing, offer to open", selection: $settings.musicPlayer) {
                    ForEach(MusicPlayer.allCases) { Text($0.title).tag($0) }
                }
                if services.media.musicPlayer != settings.musicPlayer {
                    Text("\(settings.musicPlayer.title) isn't installed, so Music opens instead.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Clock

struct ClockPane: View {
    @Environment(AppServices.self) private var services
    @State private var zoneQuery = ""

    var body: some View {
        @Bindable var settings = services.settings
        Form {
            Section("Beside the Notch") {
                Toggle("Show the time when nothing else is going on", isOn: $settings.showIdleClock)
            }
            Section {
                ForEach(settings.worldClockIDs, id: \.self) { id in
                    HStack {
                        Text(TimeZone(identifier: id).map(ClockCard.cityName) ?? id)
                        Spacer()
                        Button(role: .destructive) {
                            settings.worldClockIDs.removeAll { $0 == id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .help("Remove")
                    }
                }
                if settings.worldClockIDs.count < 3 {
                    TextField("Add a city", text: $zoneQuery, prompt: Text("Search time zones, e.g. Tokyo"))
                    ForEach(zoneMatches, id: \.self) { id in
                        Button {
                            settings.worldClockIDs.append(id)
                            zoneQuery = ""
                        } label: {
                            Label(id.replacingOccurrences(of: "_", with: " "), systemImage: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("World Clocks")
            } footer: {
                Text("Up to two are shown on the Clock card.")
            }
        }
    }

    /// Zones whose identifier or city in DyNotch's language matches: "Tokio" finds Asia/Tokyo.
    private var zoneMatches: [String] {
        let query = zoneQuery.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }
        return TimeZone.knownTimeZoneIdentifiers
            .filter { id in
                !services.settings.worldClockIDs.contains(id)
                    && (id.localizedCaseInsensitiveContains(query.replacingOccurrences(of: " ", with: "_"))
                        || TimeZone(identifier: id).map(ClockCard.cityName)?.localizedStandardContains(query) == true)
            }
            .prefix(5)
            .map { $0 }
    }
}

// MARK: - Weather

struct WeatherPane: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var settings = services.settings
        Form {
            Section {
                Toggle("Use my current location", isOn: $settings.weatherUseLocation)
                    .onChange(of: settings.weatherUseLocation) { refresh() }
                if settings.weatherUseLocation {
                    PermissionNotice(.location, "Needs Location to find where you are.")
                } else {
                    CityPicker()
                }
            } header: {
                Text("Location")
            } footer: {
                if !settings.weatherUseLocation {
                    Text("Add a region or country to narrow it down, e.g. “Portland, Oregon”.")
                }
            }
            Section {
                Picker("Temperature", selection: $settings.temperatureUnit) {
                    ForEach(TemperatureUnitPreference.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.temperatureUnit) { refresh() }
                LabeledContent("Forecast") {
                    Button("Refresh Now") { refresh() }
                }
            } footer: {
                Text("Weather data by Open-Meteo.com (CC BY 4.0).")
            }
        }
    }

    private func refresh() {
        Task { await services.weather.refresh() }
    }
}

// MARK: - Calendar & Reminders

struct CalendarPane: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var settings = services.settings
        let events = services.events
        Form {
            Section("Calendars") {
                if events.hasCalendarAccess {
                    ForEach(events.calendars) { calendar in
                        Toggle(isOn: visibility(calendar.id, in: $settings.hiddenCalendarIDs)) {
                            Label {
                                Text(calendar.title)
                                Text(calendar.source)
                            } icon: {
                                Circle().fill(calendar.color).frame(width: 10, height: 10)
                            }
                        }
                    }
                } else {
                    PermissionNotice(.calendars, "Needs Calendars to show your events.")
                }
            }
            Section("Reminder Lists") {
                if events.hasRemindersAccess {
                    ForEach(events.reminderLists) { list in
                        Toggle(isOn: visibility(list.id, in: $settings.hiddenReminderListIDs)) {
                            Label {
                                Text(list.title)
                            } icon: {
                                Circle().fill(list.color).frame(width: 10, height: 10)
                            }
                        }
                    }
                } else {
                    PermissionNotice(.reminders, "Needs Reminders to show what's due.")
                }
            }
            Section {
                Toggle(isOn: $settings.liveMeetings) {
                    Text("Offer to join online meetings")
                    Text("Zoom, Meet, Teams, Webex and FaceTime links in events pop up with Join 5 minutes before and when they start.")
                }
            } header: {
                Text("Meetings")
            }
        }
        .onAppear { events.refresh() }
        .onChange(of: settings.hiddenCalendarIDs) { events.refresh() }
        .onChange(of: settings.hiddenReminderListIDs) { events.refresh() }
    }

    private func visibility(_ id: String, in hidden: Binding<[String]>) -> Binding<Bool> {
        Binding {
            !hidden.wrappedValue.contains(id)
        } set: { visible in
            if visible { hidden.wrappedValue.removeAll { $0 == id } } else { hidden.wrappedValue.append(id) }
        }
    }
}

// MARK: - Timers

struct TimersPane: View {
    @Environment(AppServices.self) private var services
    /// Plays a tone once as it's picked, as the iPhone does.
    @State private var tonePreview = AlarmPlayer()

    var body: some View {
        @Bindable var settings = services.settings
        Form {
            Section {
                ForEach(settings.timerOrder) { mode in
                    TimerOrderRow(mode: mode, settings: settings)
                }
            } header: {
                Text("Order")
            } footer: {
                Text("You can also drag them up and down in the notch's Timers tab.")
            }
            Section("Pomodoro") {
                ValueStepper(title: "Focus", value: $settings.pomodoroWorkMinutes, range: 1...90, step: 5, unit: "min")
                ValueStepper(title: "Short break", value: $settings.pomodoroShortBreakMinutes, range: 1...90, unit: "min")
                ValueStepper(title: "Long break", value: $settings.pomodoroLongBreakMinutes, range: 1...90, step: 5, unit: "min")
                ValueStepper(title: "Rounds before a long break", value: $settings.pomodoroRounds, range: 1...100)
            }
            Section("When a Timer Ends") {
                Toggle("Play a sound", isOn: $settings.timerSound)
                if settings.timerSound {
                    Toggle(isOn: $settings.timerAlarm) {
                        Text("Ring until stopped")
                        Text("Like an iPhone timer, the sound repeats until you click Stop, for up to 5 minutes.")
                    }
                    if settings.timerAlarm {
                        Picker("Alarm sound", selection: $settings.timerAlarmTone) {
                            ForEach(AlarmTone.all) { tone in
                                Text(tone == .standard ? String(localized: "\(tone.name) (Default)") : tone.name).tag(tone.id)
                            }
                        }
                    }
                }
                Toggle("Send a notification", isOn: $settings.timerNotification)
                if settings.timerNotification {
                    PermissionNotice(.notifications, "Needs Notifications to alert you.")
                }
            }
        }
        .onChange(of: settings.timerAlarmTone) {
            tonePreview.play(AlarmTone(id: settings.timerAlarmTone), repeating: false)
        }
        .onDisappear { tonePreview.stop() }
    }
}

/// A number to type or step, with its stepper after it, as System Settings shows them. What's
/// typed is kept as it's typed, held to the range, so closing Settings without pressing Return
/// doesn't lose it. Return, or a click anywhere outside the field, ends the typing and shows the
/// number that was kept.
private struct ValueStepper: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit: LocalizedStringKey?

    @State private var text = ""
    @FocusState private var isEditing: Bool
    /// Watches for clicks while the field is being typed in.
    @State private var clickMonitor: Any?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 44)
                    .focused($isEditing)
                    .onSubmit { isEditing = false }
                    .onKeyPress(.upArrow) { stepped(up: true); return .handled }
                    .onKeyPress(.downArrow) { stepped(up: false); return .handled }
                if let unit {
                    Text(unit)
                }
                Stepper(title, onIncrement: { stepped(up: true) }, onDecrement: { stepped(up: false) })
                    .labelsHidden()
            }
        }
        .onAppear(perform: showKept)
        .onChange(of: text) {
            if let typed, typed != value { value = typed }
        }
        // Stepping rewrites the field; typing "0" (kept as 1) doesn't until the field is left.
        .onChange(of: value) {
            if typed != value { showKept() }
        }
        .onChange(of: isEditing) {
            if isEditing {
                endEditingOnClickOutside()
            } else {
                stopWatchingClicks()
                showKept()
            }
        }
        .onDisappear(perform: stopWatchingClicks)
    }

    /// AppKit keeps a field in focus when a click lands on the window's background, so any
    /// click outside the field ends the typing first; the click then goes on as usual (a click
    /// on the stepper still steps, one on another field starts typing there).
    private func endEditingOnClickOutside() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            if let window = event.window,
               let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
               let field = editor.delegate as? NSView,
               !field.bounds.contains(field.convert(event.locationInWindow, from: nil)) {
                window.makeFirstResponder(nil)
            }
            return event
        }
    }

    private func stopWatchingClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    /// The typed number held to the range; nil while the field holds no number.
    private var typed: Int? {
        Int(text.trimmingCharacters(in: .whitespaces)).map { min(max($0, range.lowerBound), range.upperBound) }
    }

    /// "0" becomes 1, "150" becomes 90, and an empty field goes back to the number it had.
    private func showKept() {
        text = "\(value)"
    }

    /// Steps land on multiples of the step, so 23 goes up to 25 and down to 20.
    private func stepped(up: Bool) {
        let next = up ? (value / step + 1) * step : ((value + step - 1) / step - 1) * step
        value = min(max(next, range.lowerBound), range.upperBound)
    }
}

/// Timer, Stopwatch or Pomodoro in the Timers tab's list, with a menu to move it.
private struct TimerOrderRow: View {
    let mode: TimerMode
    let settings: AppSettings

    var body: some View {
        let order = settings.timerOrder
        LabeledContent {
            Menu {
                Button("Move Up") { settings.timerOrder = LayoutOrder.moved(mode, by: -1, in: order) }
                    .disabled(order.first == mode)
                Button("Move Down") { settings.timerOrder = LayoutOrder.moved(mode, by: 1, in: order) }
                    .disabled(order.last == mode)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Move \(mode.title)")
        } label: {
            Label(mode.title, systemImage: mode.symbol)
                .labelStyle(AlignedIconLabelStyle())
        }
    }
}

// MARK: - Camera

struct CameraPane: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var settings = services.settings
        Form {
            Section {
                Picker(selection: $settings.cameraSize) {
                    ForEach(CameraSize.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Picture size")
                    Text("Large makes the notch taller while the Camera tab shows.")
                }
                Toggle(isOn: $settings.cameraMirrored) {
                    Text("Mirror the picture")
                    Text("Off, it shows you as others see you. Clicking the picture in the notch flips it too.")
                }
                PermissionNotice(.camera, "Needs Camera to show the picture.")
            } footer: {
                Text("The camera turns off as soon as the notch closes.")
            }
        }
    }
}
