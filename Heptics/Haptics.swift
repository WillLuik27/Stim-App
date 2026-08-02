import CoreHaptics
import UIKit

/// Base strength of every feedback in the app, softest to hardest.
///
/// These are the *unprofiled* values — the active `HapticProfile` scales all of
/// them, so this table sets the hierarchy and the profile sets the character.
enum Strength {
    /// Texture under a slow drag — should sit just at the edge of noticeable.
    static let grainMin: Float = 0.10
    /// Texture under a fast, far-out drag.
    static let grainMax: Float = 0.55

    /// The underlying buzz while moving, at rest and at full pull.
    static let buzzMin: Float = 0.06
    static let buzzMax: Float = 0.72

    /// Spring-back thump when you let go.
    static let settle: Float = 0.80
    /// Two lumps of goo running back into one.
    static let blend: Float = 0.55
    /// Click when a blob hits the edge of the screen.
    static let edge: Float = 0.92
    /// A neck pinching off. Second only to the tap.
    static let snap: Float = 0.96
    /// Shake rumble.
    static let rumble: Float = 1.0
    /// Tap. The hardest hit in the app, by design.
    static let tap: Float = 1.0
}

/// Thin wrapper over Core Haptics.
///
/// Two channels run at once:
///  - a single looping *continuous* player whose intensity and sharpness are
///    driven in real time while the orb is being moved, and
///  - one-shot *transient* patterns for taps, edge hits, settles and shakes.
///
/// On hardware without Core Haptics we fall back to `UIImpactFeedbackGenerator`
/// so the app still does something reasonable.
final class Haptics {

    static let shared = Haptics()

    /// The active feel. Scales and shapes everything played from here on.
    /// Matches the default in `Preferences`, so the very first haptic of a fresh
    /// launch is already the right one even if it beats the prefs being loaded.
    var profile: HapticProfile = .aggressive

    private(set) var supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var continuousRunning = false
    private var grainPlayer: CHHapticPatternPlayer?

    /// Base sharpness the modulated players are built with. `sharpnessOffset`
    /// maps our absolute 0...1 sharpness onto a shift around this.
    private static let modulatedBaseSharpness: Float = 0.5

    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)

    private init() {
        createEngine()
    }

    // MARK: - Engine lifecycle

    private func createEngine() {
        guard supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false

            // Both handlers are invoked on an internal Core Haptics thread, while
            // the player state they touch is otherwise only read/written on main.
            // Hop to main so there's a single owner and no data race.
            engine.stoppedHandler = { [weak self] _ in
                DispatchQueue.main.async { self?.continuousRunning = false }
            }
            // The engine is reset out from under us on interruptions (calls,
            // audio session changes). Rebuild the players when that happens.
            engine.resetHandler = { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.continuousRunning = false
                    self.continuousPlayer = nil
                    self.grainPlayer = nil
                    try? self.engine?.start()
                    self.makePlayers()
                }
            }

            try engine.start()
            self.engine = engine
            makePlayers()
        } catch {
            supportsHaptics = false
        }
    }

    func start() {
        guard supportsHaptics else { return }
        if engine == nil {
            createEngine()
        } else {
            try? engine?.start()
            if continuousPlayer == nil || grainPlayer == nil { makePlayers() }
        }
    }

    func stop() {
        stopContinuous()
        engine?.stop(completionHandler: nil)
    }

    // MARK: - Continuous (movement) channel

    private func makePlayers() {
        guard let engine else { return }

        // Base intensity is 1.0, NOT 0. `hapticIntensityControl` is documented as
        // multiplicative — 0.0 means "reduced by the maximum amount", 1.0 means
        // "no effect" — so a base of 0 can never be felt no matter what we send.
        // Base sharpness sits mid-range because its control is a -1...1 shift.
        let bed = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Self.modulatedBaseSharpness)
            ],
            relativeTime: 0,
            duration: 30
        )
        continuousPlayer = try? engine.makeAdvancedPlayer(with: CHHapticPattern(events: [bed], parameters: []))
        continuousPlayer?.loopEnabled = true

        // One reusable click for the movement texture, retriggered rather than
        // rebuilt — see `grain(intensity:sharpness:)`.
        let click = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Self.modulatedBaseSharpness)
            ],
            relativeTime: 0
        )
        grainPlayer = try? engine.makePlayer(with: CHHapticPattern(events: [click], parameters: []))
    }

    func startContinuous() {
        guard supportsHaptics, !continuousRunning, let player = continuousPlayer else { return }
        // Cheap insurance: if the engine was stopped by an interruption, this
        // brings it back before we try to play into it.
        try? engine?.start()
        do {
            try player.start(atTime: CHHapticTimeImmediate)
            continuousRunning = true
        } catch {
            continuousRunning = false
        }
    }

    /// Drives the looping buzz. Safe to call every frame.
    func updateContinuous(intensity: Float, sharpness: Float) {
        guard supportsHaptics, continuousRunning, let player = continuousPlayer else { return }
        let params = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: scaledIntensity(intensity), relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                     value: sharpnessOffset(sharpness), relativeTime: 0)
        ]
        try? player.sendParameters(params, atTime: CHHapticTimeImmediate)
    }

    func stopContinuous() {
        guard continuousRunning, let player = continuousPlayer else { return }
        try? player.stop(atTime: CHHapticTimeImmediate)
        continuousRunning = false
    }

    // MARK: - One-shot patterns

    /// The movement texture click.
    ///
    /// This fires up to ~70 times a second during a fast drag, so it retriggers a
    /// single pre-built player and varies it with dynamic parameters. Building a
    /// fresh `CHHapticPatternPlayer` per click — which is what `transient` does —
    /// allocates enough at that rate to make the engine audibly stutter.
    func grain(intensity: Float, sharpness: Float) {
        guard supportsHaptics, let grainPlayer else {
            fallbackImpact(intensity)
            return
        }
        let params = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: scaledIntensity(intensity), relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                     value: sharpnessOffset(sharpness), relativeTime: 0)
        ]
        try? grainPlayer.sendParameters(params, atTime: CHHapticTimeImmediate)
        try? grainPlayer.start(atTime: CHHapticTimeImmediate)
    }

    /// Single click. Used for one-off feedback that isn't on a hot path.
    func transient(intensity: Float, sharpness: Float) {
        guard supportsHaptics else {
            fallbackImpact(intensity)
            return
        }
        play(events: [
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [intensityParam(intensity), sharpnessParam(sharpness)],
                          relativeTime: 0)
        ])
    }

    /// Hard slam when the orb is tapped — the strongest thing the app plays, and
    /// the haptic half of the screen flash.
    ///
    /// A transient alone is over in a few milliseconds and reads as a "tick". The
    /// short continuous body underneath it is what gives the hit weight. The
    /// profile decides how long that body runs and what follows the strike.
    func tap() {
        guard supportsHaptics else {
            heavyImpact.impactOccurred(intensity: CGFloat(clamp(profile.intensity)))
            return
        }
        let body = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [intensityParam(Strength.tap * 0.9), sharpnessParam(0.5)],
            relativeTime: 0.004,
            duration: profile.tapBody
        )
        let decay = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1.0),
                CHHapticParameterCurve.ControlPoint(relativeTime: profile.tapBody, value: 0.0)
            ],
            relativeTime: 0.004
        )

        var events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [intensityParam(Strength.tap), sharpnessParam(0.95)],
                          relativeTime: 0),
            body
        ]
        for knock in profile.tapKnocks {
            events.append(
                CHHapticEvent(eventType: .hapticTransient,
                              parameters: [intensityParam(Strength.tap * knock.intensity),
                                           sharpnessParam(knock.sharpness)],
                              relativeTime: knock.time)
            )
        }
        play(events: events, curves: [decay])
    }

    /// Firm click when a blob runs into the edge of the screen.
    func edge() {
        transient(intensity: Strength.edge, sharpness: 1.0)
    }

    /// A neck letting go.
    ///
    /// The moment the whole gesture is built around, so it is the only thing other
    /// than a tap that hits at full force. Three parts: a bright strike as the
    /// thread parts, a very short body that falls away fast, and a low knock
    /// underneath as the droplet closes back up around itself.
    func snap(strength: Float) {
        guard supportsHaptics else {
            rigidImpact.impactOccurred(intensity: CGFloat(clamp(strength * profile.intensity)))
            return
        }
        let s = clamp(strength) * Strength.snap
        let body: TimeInterval = 0.09

        let decay = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1.0),
                CHHapticParameterCurve.ControlPoint(relativeTime: body, value: 0.0)
            ],
            relativeTime: 0.004
        )
        play(events: [
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [intensityParam(s), sharpnessParam(1.0)],
                          relativeTime: 0),
            CHHapticEvent(eventType: .hapticContinuous,
                          parameters: [intensityParam(s * 0.55), sharpnessParam(0.75)],
                          relativeTime: 0.004,
                          duration: body),
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [intensityParam(s * 0.60), sharpnessParam(0.15)],
                          relativeTime: body + 0.03)
        ], curves: [decay])
    }

    /// Two lumps of goo running back together. Low, soft, and swelling rather than
    /// striking — the exact opposite of `snap`.
    func blend(strength: Float) {
        guard supportsHaptics else {
            softImpact.impactOccurred(intensity: CGFloat(clamp(strength * profile.intensity * 0.6)))
            return
        }
        let s = clamp(strength) * Strength.blend
        let duration: TimeInterval = 0.17

        let swell = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.15),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.055, value: 1.0),
                CHHapticParameterCurve.ControlPoint(relativeTime: duration, value: 0.0)
            ],
            relativeTime: 0
        )
        play(events: [
            CHHapticEvent(eventType: .hapticContinuous,
                          parameters: [intensityParam(s), sharpnessParam(0.05)],
                          relativeTime: 0,
                          duration: duration)
        ], curves: [swell])
    }

    /// Soft decaying thump as the orb springs back to centre.
    func settle(strength: Float) {
        guard supportsHaptics else {
            softImpact.impactOccurred(intensity: CGFloat(clamp(strength * profile.intensity)))
            return
        }
        let s = clamp(strength) * Strength.settle
        let body = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [intensityParam(0.6 * s), sharpnessParam(0.1)],
            relativeTime: 0.01,
            duration: 0.25
        )
        let decay = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1.0),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.25, value: 0.0)
            ],
            relativeTime: 0.01
        )
        play(events: [
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [intensityParam(0.75 * s), sharpnessParam(0.3)],
                          relativeTime: 0),
            body
        ], curves: [decay])
    }

    /// Big swelling rumble triggered by shaking the device.
    func rumble(strength: Float) {
        guard supportsHaptics else {
            heavyImpact.impactOccurred(intensity: CGFloat(clamp(strength * profile.intensity)))
            return
        }
        let s = clamp(strength) * Strength.rumble
        let duration = 0.55

        var events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [intensityParam(s), sharpnessParam(0.75)],
                          relativeTime: 0),
            CHHapticEvent(eventType: .hapticContinuous,
                          parameters: [intensityParam(s), sharpnessParam(0.2)],
                          relativeTime: 0,
                          duration: duration)
        ]
        // A few off-beat knocks so the rumble reads as chaotic rather than a flat buzz.
        for (i, t) in [0.09, 0.17, 0.28, 0.41].enumerated() {
            events.append(
                CHHapticEvent(eventType: .hapticTransient,
                              parameters: [intensityParam(s * Float(0.8 - Double(i) * 0.15)),
                                           sharpnessParam(0.5)],
                              relativeTime: t)
            )
        }

        let swell = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.85),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.12, value: 1.0),
                CHHapticParameterCurve.ControlPoint(relativeTime: duration, value: 0.0)
            ],
            relativeTime: 0
        )
        play(events: events, curves: [swell])
    }

    /// A short taste of the active profile, played when one is picked in settings.
    /// Walks the profile's phrase so its character is audible immediately, then
    /// lands on the tap so you feel the top of its range.
    func demo() {
        guard supportsHaptics, engine != nil else {
            fallbackImpact(0.8)
            return
        }
        let steps = profile.phrase.isEmpty ? [0.30, 0.45, 0.60, 0.75] : profile.phrase
        let spacing = max(profile.grainInterval * 3, 0.07)

        var events: [CHHapticEvent] = []
        var time: TimeInterval = 0
        for step in steps {
            let wobble = Double(profile.jitter) * Double.random(in: -0.4...0.4) * spacing
            events.append(
                CHHapticEvent(eventType: .hapticTransient,
                              parameters: [intensityParam(Strength.grainMax), sharpnessParam(step)],
                              relativeTime: max(time + wobble, 0))
            )
            time += spacing
        }
        events.append(
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [intensityParam(Strength.tap), sharpnessParam(0.9)],
                          relativeTime: time + 0.06)
        )
        play(events: events)
    }

    // MARK: - Helpers

    private func play(events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []) {
        guard let engine else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            // A failed one-shot is not worth surfacing; the engine's resetHandler
            // will recover the session if it genuinely died.
        }
    }

    private func fallbackImpact(_ intensity: Float) {
        softImpact.impactOccurred(intensity: CGFloat(scaledIntensity(intensity)))
    }

    private func intensityParam(_ value: Float) -> CHHapticEventParameter {
        CHHapticEventParameter(parameterID: .hapticIntensity, value: scaledIntensity(value))
    }

    private func sharpnessParam(_ value: Float) -> CHHapticEventParameter {
        CHHapticEventParameter(parameterID: .hapticSharpness, value: scaledSharpness(value))
    }

    private func scaledIntensity(_ value: Float) -> Float {
        clamp(value * profile.intensity)
    }

    private func scaledSharpness(_ value: Float) -> Float {
        clamp(value * profile.sharpness)
    }

    /// `hapticSharpnessControl` is a *shift* in -1...1 around the event's own
    /// sharpness, not an absolute value. The rest of the app thinks in absolute
    /// 0...1, so map that onto a shift around the base the players are built with.
    private func sharpnessOffset(_ absolute: Float) -> Float {
        let shift = (scaledSharpness(absolute) - Self.modulatedBaseSharpness) * 2
        return min(max(shift, -1), 1)
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
