import SwiftUI
import UIKit

/// Owns the orb's position and translates every gesture into haptics.
final class OrbController: ObservableObject {

    /// Diameter of the orb, in points. The lone element on screen.
    static let orbDiameter: CGFloat = 200
    /// How far the orb is allowed to visually drift from centre, in points.
    /// Deliberately small — the orb should read as anchored, not thrown around.
    static let travelLimit: CGFloat = 26

    /// Finger distance that counts as a full-strength pull. Much larger than
    /// `travelLimit`, so the haptics keep responding long after the orb has
    /// stopped moving — you feel the strain rather than see it.
    private static let reachDistance: CGFloat = 170

    @Published var offset: CGSize = .zero
    @Published var isDragging = false
    /// 0...1 how hard the orb is being pulled. Drives the haptics and the glow.
    @Published var pull: CGFloat = 0
    /// 0...1 recent movement speed. Drives the glow and the buzz sharpness.
    @Published var speed: CGFloat = 0
    /// 0...1 opacity of the full-screen flash fired by a tap.
    @Published var flash: CGFloat = 0
    /// Unit vector in screen space pointing from the orb toward the light. Held
    /// fixed against the real world by `MotionSensor`.
    @Published var light = CGVector(dx: -0.707, dy: -0.707)

    private let motion = MotionSensor()

    private var lastTranslation: CGSize = .zero
    private var lastMoveTime: TimeInterval = 0
    /// Distance travelled since the last "grain" click was emitted.
    private var grainAccumulator: CGFloat = 0
    private var lastGrainTime: TimeInterval = 0
    /// Position within the active profile's phrase.
    private var phraseIndex = 0
    private var wasAtEdge = false
    private var didMoveDuringDrag = false

    /// Past this much travel in a drag, a release is a drag-end rather than a tap.
    private let tapSlop: CGFloat = 12

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
    }

    func onAppear() {
        Haptics.shared.start()
        motion.start()
    }

    func onDisappear() {
        motion.stop()
        Haptics.shared.stop()
        // Never leave the user's screen brightness pinned at maximum.
        brightnessRestore?.cancel()
        restoreBrightness()
    }

    // MARK: - Gesture handling

    func dragChanged(_ value: DragGesture.Value) {
        if !isDragging {
            beginDrag()
        }

        let profile = Haptics.shared.profile
        let now = CACurrentMediaTime()
        let raw = value.translation
        let delta = CGSize(width: raw.width - lastTranslation.width,
                           height: raw.height - lastTranslation.height)
        let travelled = hypot(delta.width, delta.height)
        lastTranslation = raw

        if travelled > 0.5 { didMoveDuringDrag = true }

        // Instantaneous speed in points/second, normalised to a 0...1 feel range.
        let elapsed = max(now - lastMoveTime, 1.0 / 240.0)
        lastMoveTime = now
        let pointsPerSecond = travelled / CGFloat(elapsed)
        let instantSpeed = min(pointsPerSecond / 2200, 1)
        // Smooth it so the buzz doesn't flicker between frames.
        speed = speed * 0.75 + instantSpeed * 0.25

        offset = Self.clampToLimit(raw)
        pull = min(hypot(raw.width, raw.height) / Self.reachDistance, 1)

        emitGrain(travelled: travelled, now: now, profile: profile)
        reportFullPull()

        Haptics.shared.updateContinuous(
            intensity: Strength.buzzMin + (Strength.buzzMax - Strength.buzzMin) * Float(pull),
            sharpness: bedSharpness(now: now, profile: profile)
        )
    }

    func dragEnded(_ value: DragGesture.Value) {
        let releasedPull = pull
        let travelled = hypot(value.translation.width, value.translation.height)

        endDrag()

        withAnimation(.interpolatingSpring(mass: 0.7, stiffness: 190, damping: 13)) {
            offset = .zero
            pull = 0
        }
        withAnimation(.easeOut(duration: 0.25)) {
            speed = 0
        }

        if didMoveDuringDrag && travelled > tapSlop {
            Haptics.shared.settle(strength: Float(0.35 + releasedPull * 0.65))
        } else {
            Haptics.shared.tap()
            fireFlash()
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

    // MARK: - Internals

    private func beginDrag() {
        isDragging = true
        didMoveDuringDrag = false
        lastTranslation = .zero
        lastMoveTime = CACurrentMediaTime()
        grainAccumulator = 0
        lastGrainTime = 0
        phraseIndex = 0
        wasAtEdge = false
        Haptics.shared.startContinuous()
        Haptics.shared.transient(intensity: 0.45, sharpness: 0.5)
    }

    private func endDrag() {
        isDragging = false
        Haptics.shared.stopContinuous()
    }

    /// Emits a click every `grainSpacing` points of travel, so the texture is tied
    /// to distance moved rather than to time — it feels like a physical surface.
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

    /// Clicks once when the pull maxes out, so there's a felt ceiling even though
    /// the orb itself stopped moving long before this point.
    private func reportFullPull() {
        let maxed = pull >= 1
        if maxed && !wasAtEdge {
            Haptics.shared.edge()
        }
        wasAtEdge = maxed
    }

    private static func clampToLimit(_ translation: CGSize) -> CGSize {
        let distance = hypot(translation.width, translation.height)
        guard distance > travelLimit else { return translation }
        let scale = travelLimit / distance
        return CGSize(width: translation.width * scale, height: translation.height * scale)
    }
}
