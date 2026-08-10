import SwiftUI

/// One lump of goo.
///
/// The field is just a bag of these plus the necks between them, and nothing here
/// knows how it gets drawn. Everything that makes a blob read as liquid — the
/// breathing outline, the egg shape it takes on when something pulls at it, the
/// squash along its direction of travel — is expressed as a deformation of a
/// plain circle and evaluated fresh every frame in `outline(at:)`.
struct Blob: Identifiable {

    enum Kind {
        /// The permanent mass in the middle of the screen. There is exactly one.
        case core
        /// Drawn out of the core but still joined to it by a neck.
        case tethered
        /// Pinched off. Lives on its own until it runs back into something.
        case free
    }

    let id: Int
    /// Fixed random offset, so no two blobs ever breathe in step.
    let seed: CGFloat

    var kind: Kind
    var position: CGPoint
    var velocity: CGVector = .zero

    /// The radius actually drawn. It chases `targetRadius` rather than jumping to
    /// it, so goo changing hands looks like it flows rather than pops.
    var radius: CGFloat
    var targetRadius: CGFloat

    /// Identifier of the finger holding this blob, and where that finger is now.
    var touch: Int?
    var target: CGPoint = .zero
    /// Where that finger first went down, for telling a tap from a drag.
    var grabOrigin: CGPoint = .zero
    /// True when the droplet was drawn by a finger already sweeping across the
    /// glass rather than by one going down on the core. That finger is dragging
    /// by definition, so lifting it is never a tap however little ground it
    /// covers afterwards.
    var swept = false

    /// 0...1 how close the neck back to the core is to letting go.
    var tension: CGFloat = 0
    /// Egg-shaped bias toward whatever is pulling, and the direction it leans in.
    var teardrop: CGFloat = 0
    var teardropAngle: CGFloat = 0
    /// Squash along the direction of travel.
    var stretch: CGFloat = 0
    /// Extra wobble, decaying, kicked in by snaps, merges and wall hits.
    var shock: CGFloat = 0
    /// 0...1 how much of the blob is clear of the core. A droplet still sunk
    /// inside the core is part of the core as far as the eye is concerned, so it
    /// is drawn with none of its own shading — otherwise it reads as a bubble
    /// trapped under the surface rather than as a bulge forming.
    var emergence: CGFloat = 1
    /// Seconds alive.
    var age: TimeInterval = 0
    /// True while the blob is resting against a wall, so one contact makes one click.
    var againstWall = false
    /// Set on a droplet that was never really pulled out — a tap rather than a
    /// drag — so that it slides back into the core without a sound.
    var quiet = false
    /// Clock time before which the core is not allowed to swallow this droplet.
    /// A neck can let go while the droplet is still buried in the core — that is
    /// what a flick out of the middle looks like — and without a moment's grace
    /// it would be taken straight back on the next frame.
    var rejoinAfter: TimeInterval = 0

    var isCore: Bool { kind == .core }
    var isHeld: Bool { touch != nil }
    /// Area stands in for mass: goo of twice the area takes twice the shifting.
    var mass: CGFloat { radius * radius }
}

extension Blob {

    /// Samples around the outline. Enough that the straight segments between them
    /// disappear once the metaball blur has been over the shape.
    private static let samples = 72

    /// The blob's edge at a moment in time.
    ///
    /// The radius is a circle plus three cosines of different frequencies, each
    /// drifting at its own rate, so the surface never repeats and is never quite
    /// still even at rest. On top of that the blob eggs out toward whatever is
    /// pulling on it, then squashes along the direction it is travelling.
    func outline(at time: TimeInterval) -> Path {
        let t = CGFloat(time)
        let phase = seed * 2 * .pi

        // Amplitudes ride up with how hard the blob is being worked, so goo at
        // rest only just moves and goo under strain churns.
        let energy = min(tension * 0.55 + shock, 1)
        let a3 = 0.019 + energy * 0.048
        let a2 = 0.013 + energy * 0.034
        let a5 = 0.008 + energy * 0.025

        let travel = atan2(velocity.dy, velocity.dx)
        let cosT = cos(travel), sinT = sin(travel)
        let squash = stretch

        var path = Path()
        for i in 0..<Self.samples {
            let theta = CGFloat(i) / CGFloat(Self.samples) * 2 * .pi
            var r = radius * (1
                + a3 * cos(3 * theta + t * 1.70 + phase)
                + a2 * cos(2 * theta - t * 1.13 + phase * 1.7)
                + a5 * cos(5 * theta + t * 2.61 + phase * 2.3))
            r *= 1 + teardrop * cos(theta - teardropAngle)

            var x = r * cos(theta)
            var y = r * sin(theta)
            if squash > 0.001 {
                // Rotate into the frame of travel, stretch, and rotate back out.
                let lx =  x * cosT + y * sinT
                let ly = -x * sinT + y * cosT
                let sx = lx * (1 + squash)
                let sy = ly * (1 - squash * 0.72)
                x = sx * cosT - sy * sinT
                y = sx * sinT + sy * cosT
            }

            let point = CGPoint(x: position.x + x, y: position.y + y)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A circle filling in one slice of the neck between the core and something still
/// joined to it.
///
/// Necks exist only in the metaball field — they are never shaded as bodies in
/// their own right, because a neck is not a thing, it is the goo between two
/// things.
struct Neck {
    var center: CGPoint
    var radius: CGFloat
}
