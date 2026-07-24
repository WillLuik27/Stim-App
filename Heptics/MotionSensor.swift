import CoreGraphics
import CoreMotion
import Foundation
import QuartzCore

/// The single device-motion stream, feeding two things:
///
///  - **shakes**, reported with a strength, and
///  - **the light direction**, which is pinned to the real world rather than to
///    the screen. Turn on the spot and the orb's highlight and shadow stay put,
///    as if a lamp were standing in the room with you.
///
/// Only one `CMMotionManager` device-motion stream can be active at a time, so
/// both jobs are served from the same callback.
final class MotionSensor {

    /// Called with a 0...1 strength whenever a shake crosses the threshold.
    var onShake: ((Float) -> Void)?
    /// Called with a unit vector in screen space pointing from the orb toward the
    /// light. Screen space means +x is right and +y is *down*.
    var onLightMoved: ((CGVector) -> Void)?

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    // MARK: Shake tuning

    /// g-force at which a movement counts as a shake.
    private let shakeThreshold: Double = 1.3
    /// g-force treated as a maximum-strength shake.
    private let shakeCeiling: Double = 3.2
    /// Minimum gap between reported shakes, so one wobble isn't reported ten times.
    private let shakeCooldown: TimeInterval = 0.3
    private var lastShake: TimeInterval = 0

    // MARK: Light tuning

    /// Where the imaginary lamp stands, as a bearing in radians. North-west, so
    /// that facing north puts the highlight up and to the left — the resting look.
    private let lightBearing = -Double.pi / 4
    /// How much the "light comes from the sky" effect contributes on top of
    /// heading. Kept secondary so turning on the spot stays the obvious cause.
    private let skyWeight: CGFloat = 0.35
    /// Per-frame approach rate for the smoothed light vector. Low enough to kill
    /// magnetometer noise, high enough that turning doesn't feel laggy.
    private let lightSmoothing: CGFloat = 0.09
    /// Don't republish until the vector has actually moved; otherwise this drives
    /// a SwiftUI invalidation 60 times a second while the phone sits still.
    private let lightEpsilon: CGFloat = 0.004

    private var smoothedLight = CGVector(dx: -0.707, dy: -0.707)
    private var publishedLight = CGVector(dx: -0.707, dy: -0.707)
    private var hasLight = false

    init() {
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        // Lets iOS put up its calibration prompt if the magnetometer needs it.
        motion.showsDeviceMovementDisplay = true

        motion.startDeviceMotionUpdates(using: referenceFrame, to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.handleShake(data.userAcceleration)
            self.handleLight(data)
        }
    }

    func stop() {
        guard motion.isDeviceMotionActive else { return }
        motion.stopDeviceMotionUpdates()
    }

    /// Magnetic north if the magnetometer can provide it, so the light is pinned
    /// to an actual compass direction. Otherwise fall back to an arbitrary but
    /// stable reference — turning still moves the light, it just isn't tied to
    /// true north.
    private var referenceFrame: CMAttitudeReferenceFrame {
        let available = CMMotionManager.availableAttitudeReferenceFrames()
        return available.contains(.xMagneticNorthZVertical) ? .xMagneticNorthZVertical : .xArbitraryZVertical
    }

    // MARK: - Shake

    private func handleShake(_ acceleration: CMAcceleration) {
        let magnitude = sqrt(acceleration.x * acceleration.x
                             + acceleration.y * acceleration.y
                             + acceleration.z * acceleration.z)
        guard magnitude >= shakeThreshold else { return }

        let now = CACurrentMediaTime()
        guard now - lastShake >= shakeCooldown else { return }
        lastShake = now

        let normalized = (magnitude - shakeThreshold) / (shakeCeiling - shakeThreshold)
        let strength = Float(min(max(normalized, 0), 1))

        DispatchQueue.main.async { [weak self] in
            // Never fire a shake at zero strength — a barely-past-threshold shake
            // should still be felt.
            self?.onShake?(0.45 + strength * 0.55)
        }
    }

    // MARK: - Light

    private func handleLight(_ data: CMDeviceMotion) {
        // `heading` is only populated for a north-referenced frame; it reports -1
        // otherwise, in which case yaw gives an equivalent relative rotation.
        let heading = data.heading >= 0 ? data.heading * .pi / 180 : -data.attitude.yaw
        let relative = lightBearing - heading

        // Bearing to screen space: screen "up" is -y, and bearings run clockwise.
        let fromHeading = CGVector(dx: CGFloat(sin(relative)), dy: CGFloat(-cos(relative)))

        // Gravity's in-plane component points at the ground, so its negation points
        // at the sky. Held flat this is near zero and heading takes over entirely;
        // held upright it pulls the highlight toward the top of the world.
        let gravity = data.gravity
        let towardSky = CGVector(dx: CGFloat(-gravity.x), dy: CGFloat(gravity.y))

        let target = normalized(CGVector(
            dx: fromHeading.dx + towardSky.dx * skyWeight,
            dy: fromHeading.dy + towardSky.dy * skyWeight
        ))

        // Smooth as a vector, not as an angle — lerping an angle tears when it
        // wraps past north, which is exactly where people turn most.
        smoothedLight = normalized(CGVector(
            dx: smoothedLight.dx + (target.dx - smoothedLight.dx) * lightSmoothing,
            dy: smoothedLight.dy + (target.dy - smoothedLight.dy) * lightSmoothing
        ))

        let moved = abs(smoothedLight.dx - publishedLight.dx) > lightEpsilon
            || abs(smoothedLight.dy - publishedLight.dy) > lightEpsilon
        guard moved || !hasLight else { return }

        hasLight = true
        publishedLight = smoothedLight
        let light = smoothedLight
        DispatchQueue.main.async { [weak self] in
            self?.onLightMoved?(light)
        }
    }

    private func normalized(_ vector: CGVector) -> CGVector {
        let length = hypot(vector.dx, vector.dy)
        guard length > 0.0001 else { return CGVector(dx: -0.707, dy: -0.707) }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }
}
