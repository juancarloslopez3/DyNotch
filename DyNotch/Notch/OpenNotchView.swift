import SwiftUI

/// The fully open notch: tab bar in the strip beside the cut-out, tab content below.
struct OpenNotchView: View {
    @Environment(AppServices.self) private var services
    let model: NotchViewModel

    var body: some View {
        @Bindable var model = model
        let notch = model.geometry.notchSize
        let settings = services.settings

        VStack(spacing: 0) {
            WingsLayout(notch: notch) {
                // Without the tab bar, swiping moves between the tabs.
                NotchTabBar(tabs: settings.showsTabBar ? settings.visibleTabs : [], selection: $model.tab)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
            } trailing: {
                HeaderStatusView()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 18)
            }

            Group {
                switch model.tab {
                case .home: HomeTabView()
                case .shelf: ShelfTabView(model: model)
                case .timers: TimersTabView()
                case .camera: CameraTabView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .transition(tabTransition)
            .id(model.tab)
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: model.tabEdgeBump) { content, offset in
                content.offset(x: offset)
            } keyframes: { _ in
                // Past the first or last tab: a little the way the fingers went, and back.
                KeyframeTrack {
                    SpringKeyframe(CGFloat(-model.tabEdgeBump.step) * 12, duration: 0.12)
                    SpringKeyframe(0, duration: 0.4)
                }
            }
        }
        .animation(.notchQuick, value: model.tab)
    }

    /// A tab swiped to slides in from its side while the old one blurs away; one picked in the tab
    /// bar blurs in where it is.
    private var tabTransition: AnyTransition {
        guard let step = model.tabSwipeStep else { return AnyTransition(.blurReplace) }
        return .asymmetric(insertion: AnyTransition(TabSlideTransition(step: step)), removal: AnyTransition(.blurReplace))
    }
}

/// Brings a tab in from the side it's on: from the right for the next one (`step` +1).
private struct TabSlideTransition: Transition {
    let step: Int

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .offset(x: phase.isIdentity ? 0 : CGFloat(step) * 40)
            .blur(radius: phase.isIdentity ? 0 : 5)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// Glass tab switcher. The selection indicator is a glass capsule that slides between tabs.
/// A lone tab needs no switcher, so then it shows nothing.
struct NotchTabBar: View {
    let tabs: [NotchTab]
    @Binding var selection: NotchTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs.count > 1 ? tabs : []) { tab in
                Button {
                    selection = tab
                } label: {
                    NotchTabIcon(tab: tab, isSelected: selection == tab, namespace: namespace)
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .animation(.notchQuick, value: tabs)
    }
}

/// A tab's symbol; the selected one sits in a glass capsule, which slides between tabs
/// sharing a `namespace`.
struct NotchTabIcon: View {
    let tab: NotchTab
    let isSelected: Bool
    var namespace: Namespace.ID?

    var body: some View {
        Image(systemName: tab.symbol)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 34, height: 24)
            .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
            .background {
                if isSelected {
                    let capsule = Capsule()
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    if let namespace {
                        capsule.matchedGeometryEffect(id: "selection", in: namespace)
                    } else {
                        capsule
                    }
                }
            }
            .contentShape(.capsule)
            .accessibilityLabel(tab.title)
    }
}

/// Battery and settings shortcut on the right of the cut-out; each can be turned off.
struct HeaderStatusView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let settings = services.settings
        HStack(spacing: 10) {
            if settings.headerBattery, let battery = services.battery.reading {
                HStack(spacing: 4) {
                    Text("\(battery.percent)%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: BatterySymbol.name(percent: battery.percent, charging: battery.isCharging))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(BatterySymbol.color(percent: battery.percent, charging: battery.isCharging), .white.opacity(0.45))
                        .font(.system(size: 14))
                }
                .help(battery.isOnAC ? (battery.isCharging ? "Charging" : "On power adapter") : "On battery")
            }
            if settings.headerSettingsButton {
                Button {
                    SettingsWindowController.shared.show()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 26, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
    }
}

/// Rounded Liquid Glass card used for every widget inside the black notch.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 12
    var tint: Color? = nil
    /// Responds to the pointer, for a card that does something when clicked.
    var isInteractive = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(
                (tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular).interactive(isInteractive),
                in: .rect(cornerRadius: cornerRadius)
            )
    }
}

/// A glass capsule tinted with a color. Used instead of `.glassProminent`, which turns
/// gray because DyNotch is never the active app.
struct TintedGlassButtonStyle: ButtonStyle {
    var tint: Color
    /// Less padding, for a small widget.
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, isCompact ? 8 : 14)
            .padding(.vertical, isCompact ? 4 : 6)
            .background(tint.gradient, in: .capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
            .brightness(configuration.isPressed ? -0.1 : 0)
    }
}

extension ButtonStyle where Self == TintedGlassButtonStyle {
    static func tintedGlass(_ tint: Color, isCompact: Bool = false) -> TintedGlassButtonStyle {
        TintedGlassButtonStyle(tint: tint, isCompact: isCompact)
    }
}
