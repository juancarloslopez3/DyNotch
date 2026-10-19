import SwiftUI

/// A Home card with a back: clicking it turns it over around its vertical axis, like a playing
/// card, to what the front has no room for, and clicking again turns it back. Buttons on
/// either face work as usual.
struct FlipCard<Front: View, Back: View>: View {
    /// Whether there's a back to turn to. Without one the card stays put and ignores clicks.
    var canFlip = true
    @ViewBuilder var front: Front
    @ViewBuilder var back: Back

    @State private var isFlipped = false
    /// The back only exists while it shows or turns: it may hold a scroll view, which costs
    /// CPU whenever anything beside it redraws, even out of sight.
    @State private var hasBack = false
    /// Tells the end of the last turn from that of an earlier one it cut short.
    @State private var turns = 0

    var body: some View {
        let angle: Double = isFlipped ? 180 : 0
        ZStack {
            front
                .modifier(FlipFace(angle: angle, isBack: false))
            Group {
                if hasBack {
                    back
                }
            }
            .modifier(FlipFace(angle: angle, isBack: true))
        }
        .gesture(TapGesture().onEnded(turn), isEnabled: canFlip)
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if canFlip {
                Button(isFlipped ? "Turn Back" : "Show More", action: turn)
            }
        }
        .onChange(of: canFlip) {
            if !canFlip {
                isFlipped = false
                hasBack = false
            }
        }
    }

    private func turn() {
        hasBack = true
        turns += 1
        let turn = turns
        withAnimation(.flip) {
            isFlipped.toggle()
        } completion: {
            if turn == turns, !isFlipped { hasBack = false }
        }
    }
}

/// One face of a `FlipCard`, `angle` degrees into the turn: 0 shows the front, 180 the back.
/// A face shows while it's turned toward the viewer, and sinks back a little and darkens as it
/// goes edge-on. The shade is a black layer rather than `brightness`, under which Liquid Glass
/// isn't drawn at all; on the black notch it doesn't show past the card's corners.
private struct FlipFace: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let radians = angle * .pi / 180
        let isFacing = isBack ? angle > 90 : angle <= 90
        let edgeOn = abs(sin(radians))
        content
            .overlay {
                Color.black
                    .opacity(0.35 * edgeOn)
                    .allowsHitTesting(false)
            }
            .scaleEffect(1 - 0.06 * edgeOn)
            .rotation3DEffect(.radians(isBack ? radians - .pi : radians), axis: (x: 0, y: 1, z: 0), perspective: 0.3)
            .opacity(isFacing ? 1 : 0)
            .allowsHitTesting(isFacing)
            .accessibilityHidden(!isFacing)
    }
}
