import SwiftUI
import UIKit

/// A transparent sheet that reports every finger on the screen separately.
///
/// SwiftUI's `DragGesture` only ever follows one touch, which rules out the whole
/// point of the goo — a droplet under each of several fingers at once. This is the
/// smallest piece of UIKit that hands back the individual touches.
struct MultiTouchLayer: UIViewRepresentable {

    /// A rectangle, in this view's own coordinates, that touches pass straight
    /// through. The settings button lives there. Without this the sheet swallows
    /// it: UIKit hit-testing gives the touch to the topmost *view*, and a SwiftUI
    /// button drawn above this one isn't a view of its own to be found.
    var passthrough: CGRect

    var onBegan: (Int, CGPoint) -> Void
    var onMoved: (Int, CGPoint) -> Void
    var onEnded: (Int) -> Void

    func makeUIView(context: Context) -> TouchSheet {
        let view = TouchSheet()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.isOpaque = false
        apply(to: view)
        return view
    }

    func updateUIView(_ view: TouchSheet, context: Context) {
        apply(to: view)
    }

    private func apply(to view: TouchSheet) {
        view.passthrough = passthrough
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
    }

    final class TouchSheet: UIView {

        var passthrough: CGRect = .zero
        var onBegan: ((Int, CGPoint) -> Void)?
        var onMoved: ((Int, CGPoint) -> Void)?
        var onEnded: ((Int) -> Void)?

        /// Small stable integers standing in for touches. `UITouch` is only valid
        /// for the life of the touch, so it's no use as a key anywhere else.
        private var ids: [ObjectIdentifier: Int] = [:]
        private var nextID = 0

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard super.point(inside: point, with: event) else { return false }
            return !passthrough.contains(point)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                nextID += 1
                ids[ObjectIdentifier(touch)] = nextID
                onBegan?(nextID, touch.location(in: self))
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                guard let id = ids[ObjectIdentifier(touch)] else { continue }
                onMoved?(id, touch.location(in: self))
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches)
        }

        private func finish(_ touches: Set<UITouch>) {
            for touch in touches {
                guard let id = ids.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
                onEnded?(id)
            }
        }
    }
}
