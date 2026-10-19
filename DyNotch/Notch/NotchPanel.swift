import AppKit
import QuickLookUI

/// Borderless, non-activating panel that floats above the menu bar on every Space.
final class NotchPanel: NSPanel {
    /// The window that had the keyboard before `takeKeyboard()`, when it was one of DyNotch's.
    private weak var returnKeyTo: NSWindow?
    private var hasKeyboard = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        ignoresMouseEvents = true
    }

    /// Only while the Shelf has the keyboard. Otherwise AppKit could make the panel key by itself
    /// (e.g. once Quick Look closes) and take the keys from the app in front.
    override var canBecomeKey: Bool { hasKeyboard }
    override var canBecomeMain: Bool { false }

    /// Liquid Glass turns lighter, with a bright rim, in a window with the active appearance,
    /// which AppKit gives the key window. Without this, clicking the Shelf (which takes the
    /// keyboard) lit up every card in the notch. This private AppKit method is the only way to
    /// keep the look; if a later macOS drops it, the glass just lights up again.
    @objc private nonisolated func _hasActiveAppearance() -> Bool { false }

    /// Takes the keyboard without making DyNotch the active app, as Spotlight's panel does: the
    /// Shelf then gets Space, ⌘C and the arrows while the app in front stays in front.
    func takeKeyboard() {
        guard !isKeyWindow else { return }
        if !hasKeyboard {
            returnKeyTo = NSApp.keyWindow.flatMap { $0 is NotchPanel || $0 is QLPreviewPanel ? nil : $0 }
            hasKeyboard = true
        }
        makeKey()
    }

    /// Gives the keyboard back to whoever had it before `takeKeyboard()`. Quick Look, which has
    /// it while it's up, closes too.
    func returnKeyboard() {
        guard hasKeyboard else { return }
        hasKeyboard = false
        ShelfQuickLook.shared.close()
        if let window = returnKeyTo, window.isVisible {
            // DyNotch was the active app (e.g. Settings was open).
            window.makeKey()
        } else if NSApp.isActive,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            // The app in front gets its keys back. (If something since made DyNotch the active app,
            // such as a share sheet, it keeps them.)
            NSApp.deactivate()
        }
        returnKeyTo = nil
    }

    // Quick Look finds who controls it along the responder chain, which runs through the key
    // window. It asks on the main thread.

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { ShelfQuickLook.shared.hasItems }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { ShelfQuickLook.shared.take(panel) }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { ShelfQuickLook.shared.release(panel) }
    }
}
