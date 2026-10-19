import CoreGraphics
import Foundation
import Testing

@testable import DyNotch

struct NotchGeometryTests {
    @Test func hardwareNotchIsMeasuredFromAuxiliaryAreas() {
        let geometry = NotchGeometry.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 32,
            auxiliaryLeftWidth: 664,
            auxiliaryRightWidth: 664,
            menuBarHeight: 37
        )
        #expect(geometry.hasHardwareNotch)
        #expect(geometry.notchSize == CGSize(width: 184, height: 32))
        #expect(geometry.notchCenterX == 756)
    }

    @Test func screensWithoutNotchGetAVirtualOne() {
        let geometry = NotchGeometry.compute(
            screenFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
            safeAreaTop: 0,
            auxiliaryLeftWidth: nil,
            auxiliaryRightWidth: nil,
            menuBarHeight: 24
        )
        #expect(!geometry.hasHardwareNotch)
        #expect(geometry.notchSize == CGSize(width: NotchGeometry.virtualNotchWidth, height: 24))
        #expect(geometry.notchCenterX == 2792)
    }

    @Test func rectHangsFromTheTopOfTheScreen() {
        let geometry = NotchGeometry.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24
        )
        #expect(geometry.rect(for: CGSize(width: 200, height: 50)) == CGRect(x: 400, y: 750, width: 200, height: 50))
    }
}
