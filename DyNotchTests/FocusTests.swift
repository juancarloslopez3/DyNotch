import Foundation
import SwiftUI
import Testing

@testable import DyNotch

struct FocusTests {
    private func assertions(active: [String], ended: [String] = []) -> Data {
        func record(_ mode: String) -> [String: Any] {
            ["assertionDetails": ["assertionDetailsIdentifier": "com.apple.focus.activity-manager", "assertionDetailsModeIdentifier": mode]]
        }
        let store: [String: Any] = [
            "storeAssertionRecords": active.map(record),
            "storeInvalidationRecords": ended.map { ["invalidationAssertion": record($0)] },
        ]
        return try! JSONSerialization.data(withJSONObject: ["data": [store]])
    }

    private let modes = Data("""
    {"data":[{"modeConfigurations":{"com.apple.focus.work":{"mode":{
      "modeIdentifier":"com.apple.focus.work","name":"Work","symbolImageName":"briefcase.fill","tintColorName":"systemCyanColor"
    }}}}]}
    """.utf8)

    @Test func readsTheActiveModeFromModeConfigurations() throws {
        let focus = try #require(FocusMonitor.activeFocus(assertions: assertions(active: ["com.apple.focus.work"]), modes: modes))
        #expect(focus == FocusEvent(name: "Work", symbol: "briefcase.fill", color: .cyan, isOn: true))
    }

    @Test func endedAssertionsMeanNoFocus() {
        let data = assertions(active: [], ended: ["com.apple.donotdisturb.mode.default", "com.apple.sleep.sleep-mode"])
        #expect(FocusMonitor.activeFocus(assertions: data, modes: modes) == nil)
    }

    @Test func namesSystemModesWithoutConfigurations() {
        let sleep = FocusMonitor.activeFocus(assertions: assertions(active: ["com.apple.sleep.sleep-mode"], ended: ["com.apple.focus.work"]), modes: nil)
        // In DyNotch's language, which follows the Mac's.
        #expect(sleep?.name == String(localized: "Sleep"))
        let dnd = FocusMonitor.activeFocus(assertions: assertions(active: ["com.apple.donotdisturb.mode.default"]), modes: modes)
        #expect(dnd?.name == String(localized: "Do Not Disturb"))
    }
}
