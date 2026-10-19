import AppKit

/// Sharing Shelf items. SwiftUI's `ShareLink` shows nothing from a context menu in the notch's
/// panel, so this presents `NSSharingServicePicker` itself, pointing at the item or button it came
/// from. A share sheet (Messages, Notes, AirDrop…) needs DyNotch to be the active app to be typed
/// in; once it's done, the app that was in front gets the focus back.
final class ShelfSharing: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    static let shared = ShelfSharing()

    private var picker: NSSharingServicePicker?
    /// The app that was in front when DyNotch became the active app for a share sheet; it gets
    /// the focus back once the sheet is done.
    private var returnTo: NSRunningApplication?

    /// The picker is up. Like a menu, it keeps the notch open (see `NotchAttachments`).
    var isShowing: Bool { picker != nil }

    /// Shows the picker for `urls` next to `rect` in `view`'s coordinates.
    func show(_ urls: [URL], relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        guard !urls.isEmpty else { return }
        picker?.close()
        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = self
        self.picker = picker
        picker.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
    }

    /// Shares `items` with `service` straight away, as the AirDrop button does.
    func perform(_ service: NSSharingService, with items: [Any]) {
        activate()
        service.delegate = self
        service.perform(withItems: items)
    }

    private func activate() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            returnTo = front
        }
        NSApp.activate()
    }

    // MARK: - NSSharingServicePickerDelegate

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard picker === self.picker else { return }
        self.picker = nil
        if service != nil { activate() }
    }

    func sharingServicePicker(
        _ picker: NSSharingServicePicker, delegateFor sharingService: NSSharingService
    ) -> (any NSSharingServiceDelegate)? {
        self
    }

    // MARK: - NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        returnActivation()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        returnActivation()
    }

    private func returnActivation() {
        guard let app = returnTo else { return }
        returnTo = nil
        if NSApp.isActive { app.activate(from: .current) }
    }
}
