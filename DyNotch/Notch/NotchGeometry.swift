import AppKit

/// Where the (real or virtual) notch sits on a screen, in global screen coordinates.
nonisolated struct NotchGeometry: Equatable, Sendable {
    var screenFrame: CGRect
    /// Size of the closed notch. Matches the hardware cut-out when there is one.
    var notchSize: CGSize
    /// Horizontal center of the notch in global screen coordinates.
    var notchCenterX: CGFloat
    var hasHardwareNotch: Bool

    static let virtualNotchWidth: CGFloat = 185
    static let minimumVirtualHeight: CGFloat = 24

    /// Pure computation so it can be unit tested without real screens.
    static func compute(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryLeftWidth: CGFloat?,
        auxiliaryRightWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) -> NotchGeometry {
        if safeAreaTop > 0, let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
            let width = screenFrame.width - left - right
            if width > 0 {
                return NotchGeometry(
                    screenFrame: screenFrame,
                    notchSize: CGSize(width: width, height: safeAreaTop),
                    notchCenterX: screenFrame.minX + left + width / 2,
                    hasHardwareNotch: true
                )
            }
        }
        return NotchGeometry(
            screenFrame: screenFrame,
            notchSize: CGSize(width: virtualNotchWidth, height: max(menuBarHeight, minimumVirtualHeight)),
            notchCenterX: screenFrame.midX,
            hasHardwareNotch: false
        )
    }
}

extension NotchGeometry {
    @MainActor
    init(screen: NSScreen) {
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        self = NotchGeometry.compute(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: menuBarHeight > 0 ? menuBarHeight : NSStatusBar.system.thickness
        )
    }

    /// Rect (global coordinates) of a notch shape of the given size hanging from the top of the screen.
    func rect(for size: CGSize) -> CGRect {
        CGRect(
            x: notchCenterX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }
}
