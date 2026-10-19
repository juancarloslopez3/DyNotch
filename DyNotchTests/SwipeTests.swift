import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import DyNotch

struct SwipeTests {
    private typealias Frame = TrackpadTouches.Frame

    /// Three fingers down at `x`, moved by `dx`/`dy` in steps, then lifted. The tab steps given.
    private func swipe(_ recognizer: inout TouchSwipeRecognizer, from x: CGFloat = 0.5, dx: CGFloat, dy: CGFloat = 0, fingers: Int = 3) -> [Int] {
        var steps: [Int] = []
        // They come down one after another.
        for count in 1...fingers {
            if let step = recognizer.update(Frame(count: count, center: CGPoint(x: x, y: 0.5))) { steps.append(step) }
        }
        for index in 1...10 {
            let progress = CGFloat(index) / 10
            let center = CGPoint(x: x + dx * progress, y: 0.5 + dy * progress)
            if let step = recognizer.update(Frame(count: fingers, center: center)) { steps.append(step) }
        }
        for count in (0..<fingers).reversed() {
            if let step = recognizer.update(Frame(count: count, center: CGPoint(x: x + dx, y: 0.5 + dy))) { steps.append(step) }
        }
        return steps
    }

    @Test func threeFingersLeftGoToTheNextTabOncePerSwipe() {
        var recognizer = TouchSwipeRecognizer()
        #expect(swipe(&recognizer, dx: -0.3) == [1])
        #expect(swipe(&recognizer, dx: 0.3) == [-1])
        #expect(swipe(&recognizer, dx: -0.05) == [])
    }

    @Test func otherTouchGesturesAreLeftAlone() {
        var recognizer = TouchSwipeRecognizer()
        // Mission Control, then four fingers, then two (a scroll).
        #expect(swipe(&recognizer, dx: 0.05, dy: 0.3) == [])
        #expect(swipe(&recognizer, dx: -0.3, fingers: 4) == [])
        #expect(swipe(&recognizer, dx: -0.3, fingers: 2) == [])
        // Up first, then sideways, still isn't a swipe.
        _ = recognizer.update(Frame(count: 3, center: CGPoint(x: 0.5, y: 0.5)))
        #expect(recognizer.update(Frame(count: 3, center: CGPoint(x: 0.5, y: 0.65))) == nil)
        #expect(recognizer.update(Frame(count: 3, center: CGPoint(x: 0.2, y: 0.65))) == nil)
    }

    @Test func aSwipeNeedsTheFingersToComeDownFromFewer() {
        var recognizer = TouchSwipeRecognizer()
        // A fourth finger lifts mid-gesture: still the four-finger gesture.
        _ = recognizer.update(Frame(count: 4, center: CGPoint(x: 0.5, y: 0.5)))
        _ = recognizer.update(Frame(count: 3, center: CGPoint(x: 0.5, y: 0.5)))
        #expect(recognizer.update(Frame(count: 3, center: CGPoint(x: 0.2, y: 0.5))) == nil)
        #expect(swipe(&recognizer, dx: -0.3) == [1])
    }

    /// One trackpad scroll gesture: began, `moves` changes, ended, then `momentum` events. Only
    /// swipes the ways in `accepted` count; the others scroll.
    private func scroll(
        _ recognizer: inout ScrollSwipeRecognizer,
        moves: [CGSize],
        momentum: Int = 0,
        accepted: Set<ScrollSwipeRecognizer.Direction> = [.left, .right, .up, .down]
    ) -> (swipes: [ScrollSwipeRecognizer.Direction], consumed: [Bool]) {
        var swipes: [ScrollSwipeRecognizer.Direction] = []
        var consumed: [Bool] = []
        func feed(_ phase: NSEvent.Phase, _ momentumPhase: NSEvent.Phase, _ fingers: CGSize) {
            let result = recognizer.update(phase: phase, momentumPhase: momentumPhase, fingers: fingers) { accepted.contains($0) }
            if let swipe = result.swipe { swipes.append(swipe) }
            consumed.append(result.consumes)
        }
        feed(.mayBegin, [], .zero)
        feed(.began, [], .zero)
        moves.forEach { feed(.changed, [], $0) }
        feed(.ended, [], .zero)
        for index in 0..<momentum {
            feed([], index == 0 ? .began : .changed, CGSize(width: -10, height: 0))
        }
        return (swipes, consumed)
    }

    @Test func twoFingersSideways() {
        var recognizer = ScrollSwipeRecognizer()
        let left = scroll(&recognizer, moves: Array(repeating: CGSize(width: -10, height: 1), count: 8), momentum: 3)
        #expect(left.swipes == [.left])
        // Kept from the views under it from the moment it's sideways, momentum included.
        #expect(left.consumed == [false, false] + Array(repeating: true, count: 12))
        #expect(scroll(&recognizer, moves: Array(repeating: CGSize(width: 10, height: 0), count: 8)).swipes == [.right])
        #expect(scroll(&recognizer, moves: Array(repeating: CGSize(width: -3, height: 0), count: 8)).swipes == [])
    }

    @Test func twoFingersDownAndUp() {
        var recognizer = ScrollSwipeRecognizer()
        let down = scroll(&recognizer, moves: Array(repeating: CGSize(width: 1, height: 10), count: 8), momentum: 2)
        #expect(down.swipes == [.down])
        #expect(down.consumed == [false, false] + Array(repeating: true, count: 11))
        #expect(scroll(&recognizer, moves: Array(repeating: CGSize(width: -1, height: -10), count: 8)).swipes == [.up])
        // Only the way it started: down (to open), then back up, doesn't close.
        let back = scroll(&recognizer, moves: [CGSize(width: 0, height: 8)] + Array(repeating: CGSize(width: 0, height: -10), count: 8))
        #expect(back.swipes == [])
        // As much sideways as down is neither.
        let diagonal = scroll(&recognizer, moves: Array(repeating: CGSize(width: 10, height: 10), count: 8))
        #expect(diagonal.swipes == [])
        #expect(!diagonal.consumed.contains(true))
    }

    @Test func scrollingIsLeftAlone() {
        var recognizer = ScrollSwipeRecognizer()
        // Up over the closed notch, or over a list that scrolls.
        let vertical = scroll(&recognizer, moves: Array(repeating: CGSize(width: -4, height: -10), count: 12), momentum: 2, accepted: [.down])
        #expect(vertical.swipes == [])
        #expect(!vertical.consumed.contains(true))
        // Sideways over the Shelf's row when it holds more than fits.
        let overShelf = scroll(&recognizer, moves: Array(repeating: CGSize(width: -10, height: 0), count: 8), accepted: [.up, .down])
        #expect(overShelf.swipes == [])
        #expect(!overShelf.consumed.contains(true))
        // A mouse wheel has no phases.
        let wheel = recognizer.update(phase: [], momentumPhase: [], fingers: CGSize(width: -60, height: 0)) { _ in true }
        #expect(wheel.swipe == nil && !wheel.consumes)
    }
}
