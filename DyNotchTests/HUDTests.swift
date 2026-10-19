import Foundation
import Testing

@testable import DyNotch

struct HUDTests {
    @Test func steppingSnapsToTheGrid() {
        let step: Float = 1 / 16
        #expect(HUDController.stepped(0.5, by: step, step: step) == 0.5625)
        #expect(HUDController.stepped(0.51, by: step, step: step) == 0.5625)
        #expect(HUDController.stepped(0.98, by: step, step: step) == 1)
        #expect(HUDController.stepped(0.02, by: -step, step: step) == 0)
    }

    @Test func brightnessKeysFollowThePointerAndMonitorLevelsAreKept() throws {
        let suite = "app.dynotch.DyNotchTests.brightnessKeys"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.brightnessKeyScope == .pointer)
        #expect(settings.externalBrightness.isEmpty)
        settings.brightnessKeyScope = .all
        settings.externalBrightness = ["4268-41234-16843009": 0.37]

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.brightnessKeyScope == .all)
        #expect(reloaded.externalBrightness == ["4268-41234-16843009": 0.37])
    }
}
