import QuartzCore
import SwiftUI
import UIKit

/// Owns the goo: every blob on screen, the physics that moves them, and the
/// haptics that fall out of what they do.
///
/// The field is one core blob pinned near the middle of the screen plus any
/// number of droplets. Putting a finger on the core draws a droplet out of it,
/// still joined back by a neck; pull far enough and the neck lets go with a snap
/// and the droplet is yours to carry around. Every finger works its own droplet,
/// which is why this is driven by `MultiTouchLayer` rather than a `DragGesture`.
///
/// Everything runs off one `CADisplayLink`. The physics is the single source of
/// truth — the view only draws what it finds here, and the haptics are fired by
/// events in the simulation rather than directly by touches.
final class OrbController: ObservableObject {

    // MARK: - Tuning

    /// Radius of the core with nothing pulled out of it.
    static let coreRestRadius: CGFloat = 94
    /// Floor on the core, however much goo is off wandering the screen.
    private static let coreMinRadius: CGFloat = 32
    /// How far a droplet is drawn out, past the point where the neck starts to
    /// strain, before it lets go.
    ///
    /// The straining point is a fraction of the core's *current* radius rather
    /// than a fixed distance, so a core that has already given up most of its goo
    /// hands over what's left sooner. Between the two, a pinch-off lands around
    /// 135 points from the middle — comfortably inside the short side of a phone,
    /// which it has to be or the goo could only ever be split vertically.
    private static let neckSpan: CGFloat = 56
    private static let neckSlack: CGFloat = 0.85
    /// A droplet grows across this range as it is pulled out of the core.
    private static let dropletMinRadius: CGFloat = 15
    private static let dropletMaxRadius: CGFloat = 46
    /// How far outside a blob you can still get hold of it.
    private static let grabSlop: CGFloat = 26
    /// Past this much finger travel, a release is a drag rather than a tap.
    private static let tapSlop: CGFloat = 12
    /// Ceiling on blob speed, in points per second. Keeps a flicked droplet from
    /// tunnelling through a wall between frames.
    private static let speedLimit: CGFloat = 5200

    // Homing: how a loose droplet finds its way back into the core.
    //
    // The pull it sets off with is gentle, so a droplet just let go still drifts
    // away lazily. What it does *not* do is settle at a speed: the drag is light
    // enough that it keeps gaining the whole way in, and the pull itself tightens
    // as the gap closes, so the last stretch is a rush rather than a coast.
    private static let homingPull: CGFloat = 120
    /// Extra pull at the moment the surfaces touch, coming on as the square of how
    /// far the gap has closed — barely there at arm's length, dominant up close.
    private static let homingRush: CGFloat = 420
    /// Gap across which that extra comes on.
    private static let homingRange: CGFloat = 260
    private static let homingDrag: CGFloat = 0.55
    /// Sideways wander, so a droplet never travels home in a straight line. Scaled
    /// against the drag to keep the same wobble in the path.
    private static let homingWander: CGFloat = 40
    /// Most droplets allowed at once. Past this a touch on the core does nothing,
    /// rather than letting the field grind itself to a halt.
    private static let dropletLimit = 10
    /// Wall impact speed that earns a click.
    private static let wallClickSpeed: CGFloat = 260

    // MARK: - Published state

    /// Every body in the field, core first.
    @Published private(set) var blobs: [Blob] = []
    /// Circles filling in the necks. Metaball field only — never shaded as bodies.
    @Published private(set) var necks: [Neck] = []
    /// Seconds since the field started running. The wiggle is a function of this.
    @Published private(set) var clock: TimeInterval = 0

    @Published private(set) var isDragging = false
    /// 0...1 how hard the goo is being worked. Drives the haptics and the glow.
    @Published private(set) var pull: CGFloat = 0
    /// 0...1 recent movement speed. Drives the glow and the buzz sharpness.
    @Published private(set) var speed: CGFloat = 0
    /// 0...1 opacity of the full-screen flash fired by a tap.
    @Published var flash: CGFloat = 0
    /// Unit vector in screen space pointing from the goo toward the light. Held
    /// fixed against the real world by `MotionSensor`.
    @Published var light = CGVector(dx: -0.707, dy: -0.707)

    private(set) var bounds: CGSize = .zero

    var corePosition: CGPoint {
        blobs.first(where: \.isCore)?.position
            ?? CGPoint(x: bounds.width / 2, y: bounds.height / 2)
    }

    // MARK: - Internals

    private let motion = MotionSensor()

    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var nextBlobID = 0

    /// Distance travelled since the last "grain" click was emitted.
    private var grainAccumulator: CGFloat = 0
    private var lastGrainTime: TimeInterval = 0
    /// Position within the active profile's phrase.
    private var phraseIndex = 0

    /// How long the flash sits at full colour before it starts to fall off.
    private let flashHold: TimeInterval = 0.05
    /// How long the flash takes to fade out.
    private let flashFade: TimeInterval = 0.32

    private var brightnessRestore: DispatchWorkItem?
    private var savedBrightness: CGFloat?
    private var resignObserver: NSObjectProtocol?

    init() {
        motion.onShake = { [weak self] strength in
            guard let self, !self.isDragging else { return }
            Haptics.shared.rumble(strength: strength)
            self.jolt(strength: CGFloat(strength))
        }
        motion.onLightMoved = { [weak self] vector in
            self?.light = vector
        }

        // A flash forces screen brightness to maximum for ~0.4s. If the app is
        // backgrounded inside that window the view's `onDisappear` does NOT fire
        // for a root scene, so restore here too or the user is left at full glare.
        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.brightnessRestore?.cancel()
            self?.restoreBrightness()
        }
    }

    deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        link?.invalidate()
    }

    // MARK: - Lifecycle

    /// The field can't be built until we know how big the screen is.
    func setBounds(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let hadBounds = bounds.width > 1
        bounds = size

        if blobs.isEmpty {
            blobs = [Blob(id: takeID(),
                          seed: .random(in: 0...1),
                          kind: .core,
                          position: CGPoint(x: size.width / 2, y: size.height / 2),
                          radius: Self.coreRestRadius,
                          targetRadius: Self.coreRestRadius)]
        } else if !hadBounds {
            blobs[0].position = CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }

    func onAppear() {
        Haptics.shared.start()
        motion.start()
        startLink()
    }

    func onDisappear() {
        stopLink()
        motion.stop()
        releaseEverything()
        Haptics.shared.stop()
        // Never leave the user's screen brightness pinned at maximum.
        brightnessRestore?.cancel()
        restoreBrightness()
    }

    private func startLink() {
        guard link == nil else { return }
        let proxy = LinkProxy(owner: self)
        let link = CADisplayLink(target: proxy, selector: #selector(LinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTick = 0
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    /// `CADisplayLink` retains its target, so it can't be the controller itself
    /// without leaking the whole field for the lifetime of the app.
    private final class LinkProxy: NSObject {
        weak var owner: OrbController?
        init(owner: OrbController) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
    }

    private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        // Clamp: a hitch or a return from the background must not teleport
        // everything across the screen in one step.
        let raw = lastTick == 0 ? 1.0 / 60.0 : now - lastTick
        lastTick = now
        let dt = CGFloat(min(max(raw, 1.0 / 240.0), 1.0 / 30.0))
        clock += TimeInterval(dt)
        advance(dt: dt, now: now)
    }

    // MARK: - Touches

    /// A finger has gone down. It grabs whatever droplet it landed on; failing
    /// that, if it landed on the core, it starts drawing a new droplet out of it.
    func touchBegan(id: Int, at point: CGPoint) {
        guard !blobs.isEmpty else { return }
        beginDragIfNeeded()

        if let index = grabbable(at: point) {
            blobs[index].touch = id
            blobs[index].target = point
            blobs[index].grabOrigin = point
            blobs[index].shock = max(blobs[index].shock, 0.45)
            Haptics.shared.transient(intensity: 0.45, sharpness: 0.5)
            return
        }

        guard let core = blobs.firstIndex(where: \.isCore) else { return }
        let reach = blobs[core].radius + Self.grabSlop
        guard hypot(point.x - blobs[core].position.x,
                    point.y - blobs[core].position.y) <= reach,
              blobs.count - 1 < Self.dropletLimit else { return }

        var droplet = Blob(id: takeID(),
                           seed: .random(in: 0...1),
                           kind: .tethered,
                           position: point,
                           radius: Self.dropletMinRadius,
                           targetRadius: Self.dropletMinRadius)
        droplet.touch = id
        droplet.target = point
        droplet.grabOrigin = point
        blobs.append(droplet)
        blobs[core].shock = max(blobs[core].shock, 0.35)
        Haptics.shared.transient(intensity: 0.5, sharpness: 0.55)
    }

    func touchMoved(id: Int, to point: CGPoint) {
        guard let index = blobs.firstIndex(where: { $0.touch == id }) else { return }
        blobs[index].target = point
    }

    func touchEnded(id: Int) {
        guard let index = blobs.firstIndex(where: { $0.touch == id }) else { return }
        blobs[index].touch = nil

        let moved = hypot(blobs[index].target.x - blobs[index].grabOrigin.x,
                          blobs[index].target.y - blobs[index].grabOrigin.y)

        if blobs[index].kind == .tethered && moved < Self.tapSlop {
            // Never actually drew anything out — that was a tap on the orb.
            blobs[index].quiet = true
            Haptics.shared.tap()
            fireFlash()
        } else {
            Haptics.shared.settle(strength: Float(0.32 + blobs[index].tension * 0.68))
            blobs[index].shock = max(blobs[index].shock, 0.5)
        }

        if !blobs.contains(where: \.isHeld) { endDrag() }
    }

    /// Finds a droplet the finger can pick up, preferring the smallest one under
    /// it so a droplet resting on top of a bigger one is still reachable.
    private func grabbable(at point: CGPoint) -> Int? {
        var best: Int?
        for (index, blob) in blobs.enumerated() where !blob.isCore && !blob.isHeld {
            let distance = hypot(point.x - blob.position.x, point.y - blob.position.y)
            guard distance <= blob.radius + Self.grabSlop else { continue }
            if let current = best, blobs[current].radius <= blob.radius { continue }
            best = index
        }
        return best
    }

    private func releaseEverything() {
        for index in blobs.indices { blobs[index].touch = nil }
        if isDragging { endDrag() }
    }

    private func beginDragIfNeeded() {
        guard !isDragging else { return }
        isDragging = true
        grainAccumulator = 0
        lastGrainTime = 0
        phraseIndex = 0
        Haptics.shared.startContinuous()
    }

    private func endDrag() {
        isDragging = false
        Haptics.shared.stopContinuous()
    }

    // MARK: - Simulation

    private func advance(dt: CGFloat, now: TimeInterval) {
        guard bounds.width > 1, let coreIndex = blobs.firstIndex(where: \.isCore) else { return }

        let centre = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let corePosition = blobs[coreIndex].position
        let coreRadius = blobs[coreIndex].radius

        integrate(dt: dt, centre: centre, corePosition: corePosition, coreRadius: coreRadius)
        let travelled = collideWithWalls()
        stretchNecks(corePosition: corePosition, coreRadius: coreRadius)
        absorb()
        settleShapes(dt: dt, corePosition: corePosition)
        driveHaptics(travelled: travelled, now: now)
    }

    /// One semi-implicit Euler step. Held blobs hang off a spring to the finger —
    /// that lag is most of what makes them feel heavy and wet rather than glued to
    /// the fingertip.
    private func integrate(dt: CGFloat, centre: CGPoint,
                           corePosition: CGPoint, coreRadius: CGFloat) {
        let leanTargets = blobs.filter { $0.kind == .tethered }
            .map { ($0.position, $0.tension) }

        for index in blobs.indices {
            var blob = blobs[index]
            blob.age += TimeInterval(dt)

            var accel: CGVector
            if blob.isHeld {
                accel = spring(from: blob.position, to: blob.target,
                               velocity: blob.velocity, stiffness: 430, damping: 30)
            } else {
                switch blob.kind {
                case .core:
                    accel = spring(from: blob.position, to: centre,
                                   velocity: blob.velocity, stiffness: 150, damping: 17)
                    // The core leans toward whatever is being drawn out of it.
                    // Held against the centring spring above, a full-strength pull
                    // works out to about ten points of lean.
                    for (target, tension) in leanTargets {
                        let direction = unit(from: blob.position, to: target)
                        accel.dx += direction.dx * tension * 1400
                        accel.dy += direction.dy * tension * 1400
                    }
                case .tethered:
                    // Let go mid-pull: the neck hauls it straight back home.
                    // Quadrupling the stiffness and doubling the damping keeps the
                    // same amount of overshoot at twice the speed.
                    accel = spring(from: blob.position, to: corePosition,
                                   velocity: blob.velocity, stiffness: 1200, damping: 46)
                case .free:
                    // Loose on the screen, and finding its way home.
                    let direction = unit(from: blob.position, to: corePosition)
                    let distance = hypot(blob.position.x - corePosition.x,
                                         blob.position.y - corePosition.y)
                    let gap = max(distance - coreRadius - blob.radius, 0)
                    let closing = 1 - min(gap / Self.homingRange, 1)
                    let pull = Self.homingPull + Self.homingRush * closing * closing
                    let wander = CGFloat(clock) + blob.seed * 13
                    accel = CGVector(
                        dx: direction.dx * pull + cos(wander * 0.61) * Self.homingWander
                            - blob.velocity.dx * Self.homingDrag,
                        dy: direction.dy * pull + sin(wander * 0.44) * Self.homingWander
                            - blob.velocity.dy * Self.homingDrag
                    )
                }
            }

            blob.velocity.dx += accel.dx * dt
            blob.velocity.dy += accel.dy * dt

            let rate = hypot(blob.velocity.dx, blob.velocity.dy)
            if rate > Self.speedLimit {
                let scale = Self.speedLimit / rate
                blob.velocity.dx *= scale
                blob.velocity.dy *= scale
            }

            blob.position.x += blob.velocity.dx * dt
            blob.position.y += blob.velocity.dy * dt

            blobs[index] = blob
        }
    }

    /// Keeps everything on screen and returns how far the held blobs moved this
    /// frame, which is what the movement texture is metered against.
    private func collideWithWalls() -> CGFloat {
        var travelled: CGFloat = 0
        var loudest: CGFloat = 0

        for index in blobs.indices {
            var blob = blobs[index]
            let before = blob.position
            // Just inside a full body width, so goo pinned against the edge reads
            // as pressed up against it rather than as sliced off by it.
            let inset = blob.radius * 0.97
            let maxX = max(bounds.width - inset, inset)
            let maxY = max(bounds.height - inset, inset)
            // A held blob doesn't bounce — the finger is still holding it, so it
            // just flattens against the wall.
            let restitution: CGFloat = blob.isHeld ? 0 : 0.42
            var hit: CGFloat = 0

            if blob.position.x < inset {
                hit = max(hit, abs(blob.velocity.dx))
                blob.position.x = inset
                blob.velocity.dx = abs(blob.velocity.dx) * restitution
            } else if blob.position.x > maxX {
                hit = max(hit, abs(blob.velocity.dx))
                blob.position.x = maxX
                blob.velocity.dx = -abs(blob.velocity.dx) * restitution
            }
            if blob.position.y < inset {
                hit = max(hit, abs(blob.velocity.dy))
                blob.position.y = inset
                blob.velocity.dy = abs(blob.velocity.dy) * restitution
            } else if blob.position.y > maxY {
                hit = max(hit, abs(blob.velocity.dy))
                blob.position.y = maxY
                blob.velocity.dy = -abs(blob.velocity.dy) * restitution
            }

            if hit > 0 {
                if !blob.againstWall {
                    blob.againstWall = true
                    blob.shock = max(blob.shock, min(hit / 1400, 0.7))
                    loudest = max(loudest, hit)
                }
            } else {
                blob.againstWall = false
            }

            if blob.isHeld {
                travelled += hypot(blob.position.x - before.x, blob.position.y - before.y)
            }
            blobs[index] = blob
        }

        if loudest > Self.wallClickSpeed { Haptics.shared.edge() }
        return travelled
    }

    /// Grows each tethered droplet as it is drawn out, works out how strained its
    /// neck is, rebuilds the neck geometry, and snaps anything stretched too far.
    private func stretchNecks(corePosition: CGPoint, coreRadius: CGFloat) {
        var built: [Neck] = []

        for index in blobs.indices where blobs[index].kind == .tethered {
            let blob = blobs[index]
            let distance = hypot(blob.position.x - corePosition.x,
                                 blob.position.y - corePosition.y)

            // A droplet swells as it is drawn out — the further from the core, the
            // more goo has come with it.
            let drawn = min(distance / (Self.coreRestRadius + Self.neckSpan), 1)
            blobs[index].targetRadius = Self.dropletMinRadius
                + (Self.dropletMaxRadius - Self.dropletMinRadius) * drawn

            let gap = distance - coreRadius * Self.neckSlack
            let tension = min(max(gap / Self.neckSpan, 0), 1)
            blobs[index].tension = tension

            if tension >= 1 {
                // Pinch-off. The droplet recoils away from the core and the core
                // recoils back, exactly as a lava lamp does when a bead lets go.
                let away = unit(from: corePosition, to: blob.position)
                blobs[index].kind = .free
                blobs[index].tension = 0
                blobs[index].velocity.dx += away.dx * 90
                blobs[index].velocity.dy += away.dy * 90
                blobs[index].shock = 1
                if let core = blobs.firstIndex(where: \.isCore) {
                    blobs[core].velocity.dx -= away.dx * 40
                    blobs[core].velocity.dy -= away.dy * 40
                    blobs[core].shock = max(blobs[core].shock, 0.8)
                }
                Haptics.shared.snap(strength: Float(0.55 + drawn * 0.45))
                continue
            }

            built.append(contentsOf: neck(from: corePosition, radius: coreRadius,
                                          to: blob.position, radius: blob.radius,
                                          tension: tension))
        }

        necks = built
    }

    /// The chain of circles that stands in for the neck. Their radii taper from
    /// one body to the other and pinch in the middle, and the pinch tightens as
    /// the neck is stretched — so the thread thins to nothing right as it snaps.
    private func neck(from start: CGPoint, radius startRadius: CGFloat,
                      to end: CGPoint, radius endRadius: CGFloat,
                      tension: CGFloat) -> [Neck] {
        let steps = 8
        return (1..<steps).map { step in
            let t = CGFloat(step) / CGFloat(steps)
            let base = startRadius * (1 - t) + endRadius * t
            let pinch = max(1 - (0.42 + 0.56 * tension) * sin(.pi * t), 0.10)
            return Neck(center: CGPoint(x: start.x + (end.x - start.x) * t,
                                        y: start.y + (end.y - start.y) * t),
                        radius: max(base * pinch * 0.92, 5))
        }
    }

    /// Runs blobs together when they meet: back into the core, or into each other.
    private func absorb() {
        guard let coreIndex = blobs.firstIndex(where: \.isCore) else { return }
        let corePosition = blobs[coreIndex].position
        let coreRadius = blobs[coreIndex].radius

        var swallowed: [Int] = []

        for index in blobs.indices where !blobs[index].isCore {
            let blob = blobs[index]
            let distance = hypot(blob.position.x - corePosition.x,
                                 blob.position.y - corePosition.y)
            // A held droplet has to be pushed well inside the core before it is
            // taken back, so carrying one across the middle doesn't lose it.
            let reach = blob.isHeld ? coreRadius * 0.55 : coreRadius + blob.radius * 0.35
            guard distance < reach else { continue }
            if blob.isHeld && blob.kind == .tethered { continue }
            swallowed.append(index)
        }

        for index in swallowed {
            let blob = blobs[index]
            var core = blobs[coreIndex]
            let total = core.mass + blob.mass
            core.velocity = CGVector(
                dx: (core.velocity.dx * core.mass + blob.velocity.dx * blob.mass) / total,
                dy: (core.velocity.dy * core.mass + blob.velocity.dy * blob.mass) / total
            )
            let heft = min(blob.radius / Self.dropletMaxRadius, 1)
            core.shock = max(core.shock, heft * 0.7)
            blobs[coreIndex] = core
            if !blob.quiet {
                Haptics.shared.blend(strength: Float(0.3 + heft * 0.7))
            }
        }
        remove(indices: swallowed)

        mergeDroplets()
    }

    /// Two loose droplets that meet become one bigger droplet. Neither can be
    /// tethered — goo still joined to the core belongs to the core.
    private func mergeDroplets() {
        var removed = Set<Int>()

        outer: for a in blobs.indices where blobs[a].kind == .free {
            if removed.contains(a) { continue }
            for b in blobs.indices where b > a && blobs[b].kind == .free {
                if removed.contains(b) { continue }
                let first = blobs[a], second = blobs[b]
                let distance = hypot(first.position.x - second.position.x,
                                     first.position.y - second.position.y)
                guard distance < (first.radius + second.radius) * 0.5 else { continue }

                // The one being carried wins, otherwise the bigger one wins.
                let keepIndex = first.isHeld ? a : (second.isHeld ? b : (first.mass >= second.mass ? a : b))
                let loseIndex = keepIndex == a ? b : a
                let gone = blobs[loseIndex]
                var keeper = blobs[keepIndex]
                let total = keeper.mass + gone.mass

                keeper.velocity = CGVector(
                    dx: (keeper.velocity.dx * keeper.mass + gone.velocity.dx * gone.mass) / total,
                    dy: (keeper.velocity.dy * keeper.mass + gone.velocity.dy * gone.mass) / total
                )
                keeper.targetRadius = sqrt(keeper.targetRadius * keeper.targetRadius
                                           + gone.targetRadius * gone.targetRadius)
                keeper.shock = 1
                blobs[keepIndex] = keeper
                removed.insert(loseIndex)
                Haptics.shared.blend(strength: Float(0.35 + min(gone.radius / Self.dropletMaxRadius, 1) * 0.5))
                continue outer
            }
        }

        remove(indices: Array(removed))
    }

    private func remove(indices: [Int]) {
        guard !indices.isEmpty else { return }
        for index in indices.sorted(by: >) where blobs.indices.contains(index) {
            blobs.remove(at: index)
        }
    }

    /// Eases every shape parameter toward where the physics says it should be.
    /// Nothing here is allowed to jump — a radius or a lean that snaps to a new
    /// value reads as a glitch, not as liquid.
    private func settleShapes(dt: CGFloat, corePosition: CGPoint) {
        guard let coreIndex = blobs.firstIndex(where: \.isCore) else { return }

        // Goo is conserved. Whatever is out on the screen has come out of the
        // core, so the core is exactly the radius left over. Areas are compared as
        // squared radii, since the shared factor of pi cancels.
        let taken = blobs.reduce(CGFloat.zero) { total, blob in
            blob.isCore ? total : total + blob.targetRadius * blob.targetRadius
        }
        blobs[coreIndex].targetRadius = sqrt(max(
            Self.coreRestRadius * Self.coreRestRadius - taken,
            Self.coreMinRadius * Self.coreMinRadius))

        let coreRadius = blobs[coreIndex].radius

        // The core eggs out toward whatever is pulling hardest on it.
        var coreLean: CGFloat = 0
        var coreLeanAngle = blobs[coreIndex].teardropAngle
        if let strongest = blobs.filter({ $0.kind == .tethered }).max(by: { $0.tension < $1.tension }) {
            coreLean = 0.05 + strongest.tension * 0.11
            coreLeanAngle = atan2(strongest.position.y - corePosition.y,
                                  strongest.position.x - corePosition.x)
        }

        let ease = 1 - exp(-dt * 10)
        let slowEase = 1 - exp(-dt * 8)

        for index in blobs.indices {
            var blob = blobs[index]

            blob.radius += (blob.targetRadius - blob.radius) * ease

            let rate = hypot(blob.velocity.dx, blob.velocity.dy)
            let wantStretch = min(rate / 2600, 0.26) + blob.tension * 0.10
            blob.stretch += (wantStretch - blob.stretch) * slowEase

            let wantLean: CGFloat
            let wantAngle: CGFloat
            if blob.isCore {
                wantLean = coreLean
                wantAngle = coreLeanAngle
            } else if blob.kind == .tethered {
                wantLean = 0.09 + blob.tension * 0.24
                wantAngle = atan2(corePosition.y - blob.position.y,
                                  corePosition.x - blob.position.x)
            } else {
                wantLean = 0
                wantAngle = blob.teardropAngle
            }
            blob.teardrop += (wantLean - blob.teardrop) * slowEase
            blob.teardropAngle = wantAngle

            // Nothing of a droplet shows until its own body clears the core's
            // surface; from there it fades in over one radius of travel.
            if blob.kind == .tethered {
                let distance = hypot(blob.position.x - corePosition.x,
                                     blob.position.y - corePosition.y)
                let clear = distance - (coreRadius - blob.radius)
                blob.emergence += (min(max(clear / max(blob.radius, 1), 0), 1) - blob.emergence) * ease
            } else {
                blob.emergence += (1 - blob.emergence) * ease
            }

            blob.shock *= exp(-dt * 2.6)
            blobs[index] = blob
        }
    }

    // MARK: - Haptics

    private func driveHaptics(travelled: CGFloat, now: TimeInterval) {
        var fastest: CGFloat = 0
        var strain: CGFloat = 0
        for blob in blobs where blob.isHeld {
            fastest = max(fastest, hypot(blob.velocity.dx, blob.velocity.dy))
            // A tethered droplet reports the strain in its neck; a loose one has
            // no neck to strain, so what you feel is simply how hard you sling it.
            let reported = blob.kind == .tethered
                ? blob.tension
                : min(hypot(blob.velocity.dx, blob.velocity.dy) / 1400, 1) * 0.6
            strain = max(strain, reported)
        }

        // Smooth both, so neither the buzz nor the glow flickers between frames.
        speed = speed * 0.78 + min(fastest / 2200, 1) * 0.22
        pull = pull * 0.7 + strain * 0.3

        guard isDragging else { return }
        let profile = Haptics.shared.profile
        emitGrain(travelled: travelled, now: now, profile: profile)
        Haptics.shared.updateContinuous(
            intensity: Strength.buzzMin + (Strength.buzzMax - Strength.buzzMin) * Float(pull),
            sharpness: bedSharpness(now: now, profile: profile)
        )
    }

    /// Emits a click every `grainSpacing` points of travel, so the texture is tied
    /// to distance moved rather than to time — it feels like a physical surface.
    /// Travel is summed across every finger, so working two droplets at once is
    /// felt as a denser surface rather than as the same one.
    ///
    /// If the profile carries a phrase, sharpness steps through it one click at a
    /// time. Sharpness is what the skin reads as pitch, so that sequence is what
    /// turns a drag into something with a tune.
    private func emitGrain(travelled: CGFloat, now: TimeInterval, profile: HapticProfile) {
        grainAccumulator += travelled
        guard grainAccumulator >= profile.grainSpacing else { return }

        let interval = profile.grainInterval
            * (1 + Double(profile.jitter) * Double.random(in: -0.5...0.9))
        guard now - lastGrainTime >= interval else {
            // Throttled. Cap the accumulator so the skipped clicks don't bank up
            // and then all fire at once when the gate opens.
            grainAccumulator = min(grainAccumulator, profile.grainSpacing)
            return
        }

        grainAccumulator = 0
        lastGrainTime = now

        var intensity = Strength.grainMin + (Strength.grainMax - Strength.grainMin) * Float(pull)
        if profile.jitter > 0 {
            intensity *= 1 - profile.jitter * Float.random(in: 0...0.55)
        }

        let sharpness: Float
        if profile.phrase.isEmpty {
            sharpness = Float(0.3 + speed * 0.65)
        } else {
            sharpness = profile.phrase[phraseIndex % profile.phrase.count]
            phraseIndex += 1
        }

        Haptics.shared.grain(intensity: intensity, sharpness: sharpness)
    }

    /// Sharpness of the continuous bed. Normally it just tracks drag speed; a
    /// profile with `bedDrift` adds a slow wander built from two sines whose
    /// periods share no common multiple, so the bed never settles into step with
    /// the texture riding on top of it and never repeats.
    private func bedSharpness(now: TimeInterval, profile: HapticProfile) -> Float {
        var sharpness = Float(0.05 + speed * 0.9)
        guard profile.bedDrift > 0 else { return sharpness }

        let wander = Float(sin(now * 3.1) + sin(now * 7.53)) * 0.5
        sharpness += profile.bedDrift * wander * 0.45
        return min(max(sharpness, 0), 1)
    }

    /// Shakes the whole field, so a shake looks like what it feels like.
    private func jolt(strength: CGFloat) {
        for index in blobs.indices {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let kick = 220 * strength
            blobs[index].velocity.dx += cos(angle) * kick
            blobs[index].velocity.dy += sin(angle) * kick
            blobs[index].shock = min(blobs[index].shock + strength, 1)
        }
    }

    // MARK: - Flash

    /// Slams the screen to the chosen colour, holds, then falls off. Screen
    /// brightness is pushed to maximum for the duration so it throws real light
    /// rather than just showing a coloured rectangle at whatever level was set.
    func fireFlash() {
        if savedBrightness == nil {
            savedBrightness = UIScreen.main.brightness
        }
        UIScreen.main.brightness = 1.0

        // Set the peak with animations off, otherwise SwiftUI coalesces this with
        // the fade below and the flash never actually reaches full strength.
        var immediate = Transaction()
        immediate.disablesAnimations = true
        withTransaction(immediate) { flash = 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + flashHold) { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: self.flashFade)) { self.flash = 0 }
        }

        // Rapid taps keep pushing the restore out rather than stacking it.
        brightnessRestore?.cancel()
        let restore = DispatchWorkItem { [weak self] in self?.restoreBrightness() }
        brightnessRestore = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + flashHold + flashFade, execute: restore)
    }

    private func restoreBrightness() {
        guard let saved = savedBrightness else { return }
        UIScreen.main.brightness = saved
        savedBrightness = nil
    }

    // MARK: - Small maths

    private func takeID() -> Int {
        nextBlobID += 1
        return nextBlobID
    }

    private func spring(from position: CGPoint, to target: CGPoint,
                        velocity: CGVector, stiffness: CGFloat, damping: CGFloat) -> CGVector {
        CGVector(dx: (target.x - position.x) * stiffness - velocity.dx * damping,
                 dy: (target.y - position.y) * stiffness - velocity.dy * damping)
    }

    private func unit(from: CGPoint, to: CGPoint) -> CGVector {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0.0001 else { return .zero }
        return CGVector(dx: dx / length, dy: dy / length)
    }
}
