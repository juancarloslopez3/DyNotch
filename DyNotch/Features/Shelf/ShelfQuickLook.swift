import AppKit
import QuickLookUI

/// Quick Look for the Shelf. DyNotch is never the active app, so the shared panel is made
/// non-activating: like the notch itself it then takes the keyboard (Space, arrows, Esc) while
/// the app in front stays in front.
final class ShelfQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = ShelfQuickLook()

    /// The shelf the panel shows items of: where they zoom out of and back into.
    private weak var owner: ShelfController?
    private(set) var urls: [URL] = []

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    func isShowing(for owner: ShelfController) -> Bool { isVisible && self.owner === owner }

    /// Shows `urls` starting at `index`, or switches the open panel to them.
    func show(_ urls: [URL], at index: Int, for owner: ShelfController) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.owner = owner
        self.urls = urls
        panel.styleMask.insert(.nonactivatingPanel)
        if panel.isVisible {
            panel.reloadData()
        } else {
            // The notch panel, which has the keyboard, hands over control through the responder chain.
            panel.makeKeyAndOrderFront(nil)
        }
        panel.currentPreviewItemIndex = min(max(index, 0), urls.count - 1)
    }

    func close() {
        guard isVisible else { return }
        QLPreviewPanel.shared().close()
    }

    // MARK: - Panel control, handed over by `NotchPanel`

    var hasItems: Bool { !urls.isEmpty }

    func take(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func release(_ panel: QLPreviewPanel) {
        guard panel.dataSource === self else { return }
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let url = item?.previewItemURL else { return .zero }
        return owner?.screenFrame(of: url) ?? .zero
    }

    func previewPanel(
        _ panel: QLPreviewPanel!, transitionImageFor item: (any QLPreviewItem)!, contentRect: UnsafeMutablePointer<NSRect>!
    ) -> Any! {
        guard let url = item?.previewItemURL else { return nil }
        return owner?.image(of: url)
    }
}
