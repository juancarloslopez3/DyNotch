import SwiftUI

/// The notch silhouette: a body hanging from the top edge with concave "ears" where it
/// meets the menu bar and rounded bottom corners. Both radii animate.
///
/// The shape is drawn into a rect that is `2 * topRadius` wider than the body, so the
/// ears flare outwards beyond the body width.
nonisolated struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(topRadius, rect.width / 4))
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top))
        let left = rect.minX + top
        let right = rect.maxX - top

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + top), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: left + bottom, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - bottom), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

extension Animation {
    static let notch = Animation.spring(response: 0.42, dampingFraction: 0.8)
    static let notchQuick = Animation.spring(response: 0.3, dampingFraction: 0.85)
    /// Something beside the notch coming or going: a glide without bounce.
    static let notchFold = Animation.smooth(duration: 0.6)
    /// A second activity's bubble splitting off the notch like a drop, with a little give.
    static let bubbleSplit = Animation.spring(response: 0.55, dampingFraction: 0.72)
    /// The bubble flowing back into the notch.
    static let bubbleMerge = Animation.spring(response: 0.45, dampingFraction: 0.9)
    /// A card turning over.
    static let flip = Animation.spring(duration: 0.55, bounce: 0.15)
}
