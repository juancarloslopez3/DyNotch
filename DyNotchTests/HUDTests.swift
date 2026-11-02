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

    @Test func everyStepFromSettingsReachesBothEndsExactly() {
        for percent in AppSettings.hudStepRange {
            let step = Float(percent) / 100
            let presses = (100 + percent - 1) / percent
            var level: Float = 0
            for _ in 0..<presses { level = HUDController.stepped(level, by: step, step: step) }
            #expect(level == 1, "\(percent) % up")
            for _ in 0..<presses { level = HUDController.stepped(level, by: -step, step: step) }
            #expect(level == 0, "\(percent) % down")
        }
        // 5 % at a time from 50 %.
        #expect(Int((HUDController.stepped(0.5, by: 0.05, step: 0.05) * 100).rounded()) == 55)
    }

    @Test func eachLevelKeepsItsOwnStepsWithinTheirRange() throws {
        let suite = "app.dynotch.DyNotchTests.keySteps"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        for kind in [HUDKind.volume, .brightness, .keyboard] {
            #expect(settings.keyStep(for: kind, fine: false) == 0.05)
            #expect(settings.keyStep(for: kind, fine: true) == 0.02)
        }
        settings.volumeStep = 10
        settings.brightnessFineStep = 1
        defaults.set(40, forKey: "keyboardStep")
        defaults.set(0, forKey: "keyboardFineStep")

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.keyStep(for: .volume, fine: false) == 0.1)
        #expect(reloaded.keyStep(for: .volume, fine: true) == 0.02)
        #expect(reloaded.keyStep(for: .brightness, fine: false) == 0.05)
        #expect(reloaded.keyStep(for: .brightness, fine: true) == 0.01)
        #expect(reloaded.keyStep(for: .keyboard, fine: false) == 0.25)
        #expect(reloaded.keyStep(for: .keyboard, fine: true) == 0.01)
    }

    @Test func onlyPressesThatFindTheLevelAtAnEndPushPastIt() {
        #expect(HUDController.isPastEnd(1, 1))
        #expect(HUDController.isPastEnd(0, 0))
        // A display's own reading can land a hair off the end.
        #expect(HUDController.isPastEnd(0.9999, 1))
        #expect(!HUDController.isPastEnd(0.9375, 1))
        #expect(!HUDController.isPastEnd(0.0625, 0))
        #expect(!HUDController.isPastEnd(0.5, 0.5))
    }

    @Test func theSpeakerIsRedOnlyWhileSilent() {
        #expect(HUDSnapshot(kind: .volume, level: 0.4, isMuted: true).isSilent)
        #expect(HUDSnapshot(kind: .volume, level: 0).isSilent)
        #expect(!HUDSnapshot(kind: .volume, level: 0.4).isSilent)
        #expect(!HUDSnapshot(kind: .volume, level: 0, isUnavailable: true).isSilent)
        #expect(!HUDSnapshot(kind: .brightness, level: 0).isSilent)
        #expect(HUDSnapshot(kind: .volume, level: 0.4, isMuted: true).symbol == "speaker.slash.fill")
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
