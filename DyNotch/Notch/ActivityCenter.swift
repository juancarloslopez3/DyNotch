import Foundation
import Observation

/// How a live activity occupies the notch.
enum ActivityLayout: Equatable {
    /// Grows sideways only; `wing` is the width added on each side of the notch.
    case wings(CGFloat)
    /// Drops down below the notch. Width is the total width, height is added below the notch.
    case expanded(width: CGFloat, extraHeight: CGFloat)
}

/// A transient event shown in the notch for a few seconds (HUDs, device connects, ...).
struct LiveActivity: Identifiable, Equatable {
    /// Activities with the same id replace each other instead of queueing.
    var id: String
    var kind: LiveActivityKind
    /// `nil` keeps the activity until it is dismissed.
    var duration: TimeInterval?

    var priority: Int { kind.priority }
}

/// Shows one `LiveActivity` at a time, ordered by priority.
@Observable
final class ActivityCenter {
    private(set) var current: LiveActivity?

    @ObservationIgnored private var pending: [LiveActivity] = []
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func post(_ activity: LiveActivity) {
        guard let current else {
            show(activity)
            return
        }
        if current.id == activity.id || activity.priority > current.priority {
            if current.id != activity.id, current.kind.requeueWhenPreempted {
                enqueue(current)
            }
            show(activity)
        } else {
            enqueue(activity)
        }
    }

    /// Dismisses the current activity (or a specific one) and shows the next queued one.
    func dismiss(id: String? = nil) {
        if let id, current?.id != id {
            pending.removeAll { $0.id == id }
            return
        }
        dismissTask?.cancel()
        dismissTask = nil
        if pending.isEmpty {
            current = nil
        } else {
            show(pending.removeFirst())
        }
    }

    /// Updates the payload of a visible or queued activity without restarting its timer.
    func update(id: String, _ transform: (inout LiveActivity) -> Void) {
        if var activity = current, activity.id == id {
            transform(&activity)
            current = activity
        }
        if let index = pending.firstIndex(where: { $0.id == id }) {
            transform(&pending[index])
        }
    }

    private func enqueue(_ activity: LiveActivity) {
        pending.removeAll { $0.id == activity.id }
        pending.append(activity)
        pending.sort { $0.priority > $1.priority }
    }

    private func show(_ activity: LiveActivity) {
        pending.removeAll { $0.id == activity.id }
        current = activity
        dismissTask?.cancel()
        dismissTask = nil
        guard let duration = activity.duration else { return }
        let id = activity.id
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismiss(id: id)
        }
    }
}
