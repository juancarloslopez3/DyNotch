import SwiftUI

/// Settings › Layout: what the open notch shows, and in which order.
struct LayoutPane: View {
    @Environment(AppServices.self) private var services
    /// What macOS does with three-finger swipes too, read again whenever DyNotch comes back to
    /// the front (e.g. from System Settings).
    @State private var trackpadConflict = TrackpadSwipeConflict.current

    var body: some View {
        @Bindable var settings = services.settings
        Form {
            Section {
                NotchLayoutEditor()
            } footer: {
                Text("Drag a widget up, down or into another column, onto a dashed slot to start a column, or onto the tray to take it off; drag one from the tray to add it. The clock always stays. Move a column by the handle under it and the tabs sideways. Right-click a widget to resize it, and click a tab to preview it.")
            }
            Section("Tabs") {
                TabToggles(settings: settings)
                    .labelStyle(AlignedIconLabelStyle())
                Picker("Open on", selection: openingTab) {
                    Text("Last Used Tab").tag(NotchTab?.none)
                    Divider()
                    ForEach(settings.visibleTabs) { Text($0.title).tag(NotchTab?.some($0)) }
                }
                Picker("Swipe between tabs", selection: $settings.tabSwipe) {
                    Text(TabSwipe.off.title).tag(TabSwipe.off)
                    Divider()
                    ForEach([TabSwipe.twoFingers, .threeFingers]) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.tabSwipe) { services.notch.swipes.update() }
                if settings.tabSwipe == .threeFingers, let trackpadConflict {
                    SettingsNotice(trackpadConflict.message, button: String(localized: "Open Settings")) {
                        NSWorkspace.shared.open(trackpadConflict.settingsURL)
                    }
                }
                if settings.tabSwipe != .off {
                    Toggle(isOn: $settings.hideTabBar) {
                        Text("Don't show tabs")
                        Text("Swipe over the notch to move between them.")
                    }
                }
            }
            Section("Top Bar") {
                Toggle("Battery level", isOn: $settings.headerBattery)
                Toggle(isOn: $settings.headerSettingsButton) {
                    Text("Settings button")
                    Text(settings.visibleTabs.contains(.home)
                        ? "Without it, click the clock on Home to open Settings."
                        : "Without it, show the Home tab to open Settings by clicking its clock.")
                }
            }
            // The editor's widgets as lists, for moving them without dragging.
            HomeColumnSections(settings: settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trackpadConflict = TrackpadSwipeConflict.current
        }
    }

    /// A hidden opening tab reads as "Last Used Tab", which is what the notch does then.
    private var openingTab: Binding<NotchTab?> {
        let settings = services.settings
        return Binding { settings.effectiveOpeningTab } set: { settings.openingTab = $0 }
    }
}

/// Lines the titles up whatever the widths of their symbols. The symbols sit on the text's
/// baseline, so one with a badge doesn't shift its row's title.
struct AlignedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.frame(width: 20)
            configuration.title
        }
    }
}

// MARK: - Tabs

/// A switch for each tab, in tab-bar order. The last tab showing can't be turned off.
struct TabToggles: View {
    let settings: AppSettings

    var body: some View {
        ForEach(settings.tabOrder) { tab in
            Toggle(isOn: Binding { !settings.hiddenTabs.contains(tab) } set: { settings.setTab(tab, visible: $0) }) {
                Label(tab.title, systemImage: tab.symbol)
            }
            .disabled(settings.visibleTabs == [tab])
        }
    }
}

// MARK: - Home columns

/// A section per Home column, left to right: its widgets top to bottom, each large or small,
/// and a menu to add more.
private struct HomeColumnSections: View {
    let settings: AppSettings

    private static let names: [LocalizedStringResource] = ["Left Column", "Middle Column", "Right Column"]

    var body: some View {
        let columns = settings.homeLayout.columns
        ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
            Section {
                ForEach(column.cards) { card in
                    HomeCardRow(card: card, column: column, settings: settings)
                }
                AddWidgetMenu(column: column.id, settings: settings)
            } header: {
                Text(Self.names[min(index, Self.names.count - 1)])
            } footer: {
                if index == columns.count - 1 {
                    Text("A column fits two large widgets, a large one with up to two small ones, or three small ones, in any order. Next to a large widget, small ones sit side by side; on their own they fill the column, and show large when there's room. Empty columns are left out, and the others share their room.")
                }
            }
        }
    }
}

/// A widget in its column's section: large or small, and a menu to move it, or remove it unless
/// it's the clock.
private struct HomeCardRow: View {
    let card: HomeCard
    let column: HomeColumn
    let settings: AppSettings

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                // A menu rather than a picker, which can't dim the size that doesn't fit.
                Menu {
                    SizeToggles(widgets: card.widgets, isLarge: card.isLarge, settings: settings)
                } label: {
                    Text(card.isLarge ? "Large" : "Small")
                }
                .fixedSize()
                Menu {
                    CardMoveButtons(card: card, column: column, settings: settings)
                    if card.isRemovable {
                        Divider()
                        ForEach(card.widgets) { widget in
                            Button(card.widgets.count > 1 ? "Remove \(widget.title)" : "Remove") {
                                settings.homeLayout.remove(widget)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(card.isRemovable ? "Move or remove \(card.title)" : "Move \(card.title)")
            }
        } label: {
            Label(card.title, systemImage: card.symbol)
                .labelStyle(AlignedIconLabelStyle())
        }
    }
}

/// Large and Small, ticked as `widgets` are now; a size that doesn't fit is dimmed. Calendar
/// and Reminders sharing a card turn small together.
struct SizeToggles: View {
    let widgets: [HomeWidget]
    let isLarge: Bool
    let settings: AppSettings

    var body: some View {
        let layout = settings.homeLayout
        Toggle("Large", isOn: Binding { isLarge } set: { if $0, let widget = widgets.first { settings.homeLayout.makeLarge(widget) } })
            .disabled(!isLarge && !(widgets.first.map(layout.canMakeLarge) ?? false))
        Toggle("Small", isOn: Binding { !isLarge } set: { if $0 { settings.homeLayout.makeSmall(widgets) } })
            .disabled(isLarge && !layout.canMakeSmall(widgets))
    }
}

/// Move Up and Move Down for a card, or Move Left and Move Right toward a card beside it.
struct CardMoveButtons: View {
    let card: HomeCard
    let column: HomeColumn
    let settings: AppSettings

    var body: some View {
        let index = column.cards.firstIndex(of: card) ?? 0
        Button(column.areBeside(index, index - 1) ? "Move Left" : "Move Up") {
            settings.homeLayout.move(card.id, by: -1)
        }
        .disabled(index == 0)
        Button(column.areBeside(index, index + 1) ? "Move Right" : "Move Down") {
            settings.homeLayout.move(card.id, by: 1)
        }
        .disabled(index >= column.cards.count - 1)
    }
}

/// Adds a widget at the bottom of a column, large or small. One that's in another column
/// moves here.
private struct AddWidgetMenu: View {
    let column: Int
    let settings: AppSettings

    var body: some View {
        let layout = settings.homeLayout
        Menu {
            Section("Large") { choices(large: true, layout) }
            Section("Small") { choices(large: false, layout) }
        } label: {
            Label("Add Widget", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!HomeWidget.allCases.contains { layout.canAdd($0, large: true, to: column) || layout.canAdd($0, large: false, to: column) })
    }

    private func choices(large: Bool, _ layout: HomeLayout) -> some View {
        ForEach(HomeWidget.allCases) { widget in
            Button {
                settings.homeLayout.add(widget, large: large, to: column)
            } label: {
                Label(widget.title, systemImage: widget.symbol)
            }
            .disabled(!layout.canAdd(widget, large: large, to: column))
        }
    }
}
