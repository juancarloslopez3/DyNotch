import Foundation
import Testing

@testable import DyNotch

struct ActivityCenterTests {
    private func activity(_ id: String, _ kind: LiveActivityKind) -> LiveActivity {
        LiveActivity(id: id, kind: kind, duration: nil)
    }

    @Test func higherPriorityPreemptsAndLowerWaits() {
        let center = ActivityCenter()
        center.post(activity("caps", .capsLock(true)))
        center.post(activity("hud", .hud(HUDSnapshot(kind: .volume, level: 0.5))))
        #expect(center.current?.id == "hud")
        center.post(activity("song", .nowPlaying(title: "A", artist: "B", change: .skipped(forward: true))))
        #expect(center.current?.id == "hud")
        center.dismiss()
        // Caps Lock was dropped when preempted; the queued song shows next.
        #expect(center.current?.id == "song")
        center.dismiss()
        #expect(center.current == nil)
    }

    @Test func sameIdReplacesInPlace() {
        let center = ActivityCenter()
        center.post(activity("hud", .hud(HUDSnapshot(kind: .volume, level: 0.1))))
        center.post(activity("hud", .hud(HUDSnapshot(kind: .volume, level: 0.9))))
        #expect(center.current?.kind == .hud(HUDSnapshot(kind: .volume, level: 0.9)))
        center.dismiss()
        #expect(center.current == nil)
    }
}
