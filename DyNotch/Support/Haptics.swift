import AppKit

enum Haptics {
    static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        guard AppSettings.shared.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
