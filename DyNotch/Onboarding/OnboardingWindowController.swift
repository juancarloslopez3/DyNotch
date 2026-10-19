import AppKit
import ServiceManagement
import SwiftUI

/// The first-launch tour: what DyNotch does, the permissions it uses (Allow All asks for them in
/// turn), and a few things to try on the real notch, each ticked off as you do it.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?
    private let model = OnboardingModel()

    /// Shows the tour, starting over at `step` if given.
    func show(step: OnboardingStep? = nil) {
        if let step {
            model.go(to: step)
            model.tried = []
        }
        if window == nil {
            let root = OnboardingView(model: model) { [weak self] in self?.finish() }
                .environment(AppServices.shared)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = NSHostingController(rootView: root)
            // Setting the controller sized the window to its view, still empty then.
            window.setContentSize(OnboardingView.size)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        if let window, !window.isVisible { place(window) }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Brings the tour back in front, unless it's been closed: Allow All ends in System Settings.
    func bringForward() {
        guard window?.isVisible == true else { return }
        show()
    }

    /// In the middle of the screen with the notch, where you try it out.
    private func place(_ window: NSWindow) {
        guard let notch = AppServices.shared.notch.primary?.geometry,
              let screen = NSScreen.screens.first(where: { $0.frame == notch.screenFrame }) else {
            window.center()
            return
        }
        // Its full height comes with the first layout, which adds the title bar's.
        window.layoutIfNeeded()
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded()
        ))
    }

    private func finish() {
        end()
        window?.close()
    }

    /// Closed with its close button or ⌘W. Quitting DyNotch closes it too, but without asking,
    /// so the tour picks up again on the next launch.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        end()
        return true
    }

    /// Done or closed: the tour doesn't show by itself again.
    private func end() {
        AppSettings.shared.hasCompletedOnboarding = true
        AppSettings.shared.tourStepToResume = nil
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, open, tabs, shelf, hud, done
}

@Observable
final class OnboardingModel {
    private(set) var step = OnboardingStep.welcome
    /// Which way the last move went, for the page to slide in from that side.
    private(set) var direction = 1
    /// The steps whose gesture has been tried on the real notch.
    var tried: Set<OnboardingStep> = []

    func go(to step: OnboardingStep) {
        direction = step.rawValue >= self.step.rawValue ? 1 : -1
        self.step = step
        // Picked up here if DyNotch quits meanwhile: allowing Full Disk Access quits and reopens it.
        AppSettings.shared.tourStepToResume = step
    }
}

// MARK: - Window content

struct OnboardingView: View {
    static let size = CGSize(width: 600, height: 580)

    @Environment(AppServices.self) private var services
    let model: OnboardingModel
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page
                    .id(model.step)
                    .transition(AnyTransition(PageTransition(direction: model.direction)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .containerBackground(.thinMaterial, for: .window)
        .animation(.spring(duration: 0.45, bounce: 0.1), value: model.step)
        .background { TryItWatcher(model: model) }
    }

    /// The steps shown: moving between tabs needs more than one in the tab bar.
    private var steps: [OnboardingStep] {
        OnboardingStep.allCases.filter { $0 != .tabs || services.settings.visibleTabs.count > 1 }
    }

    @ViewBuilder private var page: some View {
        switch model.step {
        case .welcome: WelcomePage()
        case .permissions: PermissionsPage()
        case .open, .tabs, .shelf, .hud: TryItPage(step: model.step, isTried: model.tried.contains(model.step))
        case .done: DonePage()
        }
    }

    private var footer: some View {
        let index = steps.firstIndex(of: model.step) ?? 0
        return ZStack {
            PageDots(count: steps.count, current: index)
            HStack(spacing: 10) {
                if index > 0 {
                    Button("Back") { model.go(to: steps[index - 1]) }
                        .controlSize(.large)
                }
                Spacer()
                trailingButtons(next: steps.indices.contains(index + 1) ? steps[index + 1] : nil)
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }

    @ViewBuilder private func trailingButtons(next: OnboardingStep?) -> some View {
        let center = services.permissions
        let advance = { if let next { model.go(to: next) } }
        switch model.step {
        case .welcome:
            Button("Get Started", action: advance)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        case .permissions where !center.allGranted || center.isAllowingAll:
            Button("Continue", action: advance)
            if center.isAllowingAll {
                AllowAllButton()
            } else {
                AllowAllButton { OnboardingWindowController.shared.bringForward() }
                    .keyboardShortcut(.defaultAction)
            }
        case .permissions, .open, .tabs, .shelf, .hud:
            if model.step != .permissions, !model.tried.contains(model.step) {
                Button("Skip", action: advance)
            } else {
                Button("Continue", action: advance)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .done:
            Button("Done", action: finish)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// A page slides in from the side it's on and blurs away, as tabs do in the notch.
private struct PageTransition: Transition {
    let direction: Int

    func body(content: Content, phase: TransitionPhase) -> some View {
        let offset: CGFloat = switch phase {
        case .willAppear: CGFloat(direction) * 50
        case .identity: 0
        case .didDisappear: CGFloat(-direction) * 50
        }
        content
            .offset(x: offset)
            .blur(radius: phase.isIdentity ? 0 : 6)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// Ticks off a step once its gesture has been tried on the real notch, while that step is up.
private struct TryItWatcher: View {
    @Environment(AppServices.self) private var services
    let model: OnboardingModel

    var body: some View {
        let notches = services.notch.models
        let isOpen = notches.contains(where: \.isOpen)
        let isDropTarget = notches.contains(where: \.isShowingDropTarget)
        let isHUD = if case .hud = services.activities.current?.kind { true } else { false }
        Color.clear
            .onChange(of: isOpen) { _, open in
                if open { tried(.open) }
            }
            .onChange(of: services.settings.lastTab) {
                if isOpen { tried(.tabs) }
            }
            .onChange(of: isDropTarget) { _, shown in
                if shown { tried(.shelf) }
            }
            .onChange(of: isHUD) { _, shown in
                if shown { tried(.hud) }
            }
    }

    private func tried(_ step: OnboardingStep) {
        guard model.step == step, !model.tried.contains(step) else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { _ = model.tried.insert(step) }
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.bottom, 10)
            Text("Welcome to DyNotch")
                .font(.largeTitle.bold())
                .padding(.bottom, 8)
            Text("Your notch becomes a Dynamic Island, with your music, calendar, weather, timers, a shelf for files and the volume, all in Liquid Glass that blends into the hardware.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(.bottom, 26)
            // Wide enough for the longer Spanish names.
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(172), spacing: 12), count: 3), spacing: 12) {
                FeatureTile(title: "Now Playing", symbol: "music.note", tint: .pink)
                FeatureTile(title: "Calendar", symbol: "calendar", tint: .red)
                FeatureTile(title: "Weather", symbol: "cloud.sun.fill", tint: .cyan)
                FeatureTile(title: "Timers", symbol: "timer", tint: .orange)
                FeatureTile(title: "Shelf & AirDrop", symbol: "tray.full.fill", tint: .blue)
                FeatureTile(title: "Volume HUD", symbol: "speaker.wave.2.fill", tint: .indigo)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FeatureTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint.gradient, in: .rect(cornerRadius: 7))
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}

private struct PermissionsPage: View {
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    PermissionsList()
                } footer: {
                    Text("You can change these later in Settings › Permissions.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct TryItPage: View {
    @Environment(AppServices.self) private var services
    let step: OnboardingStep
    let isTried: Bool

    var body: some View {
        VStack(spacing: 0) {
            NotchDemo(step: step)
                .padding(.bottom, 22)
            Text(title)
                .font(.largeTitle.bold())
                .padding(.bottom, 8)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
                .padding(.bottom, 18)
            if step == .hud, services.permissions.state(.accessibility) != .granted {
                PermissionNotice(.accessibility, "Needs Accessibility to show the volume here.")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                    .frame(maxWidth: 460)
            } else {
                TryItBadge(isTried: isTried, done: done)
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settings: AppSettings { services.settings }

    private var title: LocalizedStringKey {
        switch step {
        case .open: "Open the Notch"
        case .tabs: "Move Between Tabs"
        case .shelf: "Drop Files on It"
        default: "Volume & Brightness"
        }
    }

    private var message: String {
        switch step {
        case .open:
            let open = settings.openMode == .hover
                ? String(localized: "Move the pointer up to the notch at the top of your screen: it opens, and closes again when the pointer leaves.")
                : String(localized: "Click the notch at the top of your screen. Hovering over it shows a small peek first.")
            return settings.swipeToOpen ? open + " " + String(localized: "You can also swipe down over it with two fingers, and up to close it.") : open
        case .tabs:
            let tabs = settings.visibleTabs.map(\.title).formatted(.list(type: .and))
            let twoFingers = settings.tabSwipe == .twoFingers
            if settings.tabSwipe == .off {
                return String(localized: "Open the notch and click the icons in its top-left corner to move between \(tabs).")
            } else if !settings.showsTabBar {
                return twoFingers
                    ? String(localized: "Open the notch and swipe left or right over it with two fingers to move between \(tabs).")
                    : String(localized: "Open the notch and swipe left or right over it with three fingers to move between \(tabs).")
            }
            return twoFingers
                ? String(localized: "Open the notch and swipe left or right over it with two fingers to move between \(tabs), or click their icons in its top-left corner.")
                : String(localized: "Open the notch and swipe left or right over it with three fingers to move between \(tabs), or click their icons in its top-left corner.")
        case .shelf:
            return String(localized: "Drag a file from Finder or the desktop toward the notch. Drop it on Shelf to keep it at hand, or on AirDrop to send it.")
        default:
            let levels = String(localized: "Press the volume or brightness keys: the level shows in the notch, where you can drag it too.")
            guard settings.backlightModifier != .none else { return levels }
            return levels + " " + String(localized: "Hold \(settings.backlightModifier.title) with the brightness keys for the keyboard backlight.")
        }
    }

    private var done: LocalizedStringKey {
        switch step {
        case .open: "Opened! Move the pointer away to close it."
        case .tabs: "That's it. Each tab keeps its place."
        case .shelf: "Found it! Let go on Shelf or AirDrop."
        default: "That's the new HUD."
        }
    }
}

/// "Try it now", until the step's gesture has been tried on the real notch.
private struct TryItBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isTried: Bool
    let done: LocalizedStringKey

    var body: some View {
        HStack(spacing: 7) {
            if isTried {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
                Text(done)
            } else {
                PulsingDot(isPulsing: !reduceMotion)
                    .frame(width: 7, height: 7)
                Text("Try it now")
            }
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: .capsule)
        .contentTransition(.opacity)
    }
}

/// An accent-colored dot that fades out and back, all the time. Core Animation runs it out of
/// process: as a symbol effect it cost ~12% CPU.
private struct PulsingDot: NSViewRepresentable {
    var isPulsing: Bool

    func makeNSView(context: Context) -> PulsingDotView { PulsingDotView() }

    func updateNSView(_ view: PulsingDotView, context: Context) {
        view.isPulsing = isPulsing
    }
}

private final class PulsingDotView: NSView {
    var isPulsing = false {
        didSet { updateAnimation() }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    private func updateAnimation() {
        guard let layer else { return }
        guard isPulsing else {
            layer.removeAnimation(forKey: "pulse")
            return
        }
        guard layer.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.25
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "pulse")
    }
}

private struct DonePage: View {
    @Environment(AppServices.self) private var services
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.white, .green)
                .symbolEffect(.bounce, value: hasAppeared)
                .padding(.bottom, 14)
            Text("You're All Set")
                .font(.largeTitle.bold())
                .padding(.bottom, 8)
            Text("DyNotch lives in your notch now. A few more things to know:")
                .foregroundStyle(.secondary)
            Form {
                Section {
                    TipRow(symbol: "rectangle.3.group.fill", tint: .indigo, title: "Make it yours",
                           detail: "Arrange the widgets and tabs in Settings › Layout.") {
                        Button("Open Layout") { SettingsWindowController.shared.show(pane: .layout) }
                    }
                    TipRow(symbol: "gearshape.fill", tint: .gray, title: "Settings are a click away", detail: settingsHint) {
                        EmptyView()
                    }
                    TipRow(symbol: "power", tint: .green, title: "Open DyNotch at login",
                           detail: "So the notch is ready whenever your Mac is.") {
                        Toggle("Open DyNotch at login", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
        }
        .padding(.top, 12)
        .task {
            // After the page has slid in.
            try? await Task.sleep(for: .seconds(0.35))
            hasAppeared = true
        }
    }

    private var settingsHint: LocalizedStringKey {
        let settings = services.settings
        return switch (settings.showMenuBarIcon, settings.headerSettingsButton) {
        case (true, true): "Use DyNotch's menu bar icon, or the gear in the open notch."
        case (true, false): "Use DyNotch's menu bar icon, or click the clock in the open notch."
        case (false, true): "Click the gear in the open notch."
        case (false, false): "Click the clock in the open notch."
        }
    }
}

/// A row on the last page: an icon, what to know, and something to do about it.
private struct TipRow<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: .rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}
