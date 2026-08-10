import CoreGraphics
import Foundation

/// A complete "feel" for the app.
///
/// Every haptic the app plays is scaled and shaped by the active profile, so
/// switching one changes the whole character rather than just the volume. The
/// four differ along three axes: how hard they hit (`intensity`), how sharp they
/// are (`sharpness`), and — the interesting one — whether the movement texture
/// follows a repeating `phrase` of sharpness steps, which is what makes a drag
/// read as musical rather than as noise.
struct HapticProfile: Identifiable, Equatable {

    enum Kind: String, CaseIterable {
        case aggressive, smooth, melodic, discordant
        /// A tuning the user builds themselves. Its parameters live in
        /// `Preferences`, not in the presets below.
        case custom
    }

    /// An extra hit layered into the tap pattern.
    struct Knock: Equatable {
        let time: TimeInterval
        let intensity: Float
        let sharpness: Float
    }

    let id: Kind
    let name: String
    let blurb: String
    let symbol: String

    /// Multiplies every intensity in the app.
    let intensity: Float
    /// Multiplies every sharpness. Low values round every edge off.
    let sharpness: Float

    /// Points of drag travel between texture clicks. Lower is denser.
    let grainSpacing: CGFloat
    /// Floor on the gap between texture clicks.
    let grainInterval: TimeInterval

    /// Sharpness steps the texture walks through, repeating. Sharpness is what
    /// the skin reads as pitch, so an ordered sequence here is heard as a tune.
    /// Empty means sharpness just tracks drag speed.
    let phrase: [Float]

    /// 0...1 random wobble applied to click timing and intensity.
    let jitter: Float
    /// 0...1 slow, non-repeating wander applied to the continuous bed's sharpness,
    /// so the bed drifts out of step with the texture riding on top of it.
    let bedDrift: Float

    /// Length of the continuous body underneath a tap.
    let tapBody: TimeInterval
    /// Extra hits layered into a tap after the initial strike.
    let tapKnocks: [Knock]
}

extension HapticProfile {

    static let aggressive = HapticProfile(
        id: .aggressive,
        name: "Aggressive",
        blurb: "Dense, hard and relentless. Everything hits at full force.",
        symbol: "bolt.fill",
        intensity: 1.0,
        sharpness: 1.0,
        // Two and a half points between clicks: about as fine as a fingertip can
        // move at all, so nudging the goo already sets off a run of them.
        grainSpacing: 2.5,
        grainInterval: 0.011,
        phrase: [],
        jitter: 0.10,
        bedDrift: 0,
        tapBody: 0.18,
        tapKnocks: [
            Knock(time: 0.040, intensity: 0.90, sharpness: 1.0),
            Knock(time: 0.085, intensity: 0.78, sharpness: 0.95),
            Knock(time: 0.135, intensity: 0.62, sharpness: 0.90)
        ]
    )

    static let smooth = HapticProfile(
        id: .smooth,
        name: "Smooth",
        blurb: "Soft and round. Long swells with every edge taken off.",
        symbol: "drop.fill",
        intensity: 0.55,
        sharpness: 0.20,
        grainSpacing: 15,
        grainInterval: 0.050,
        phrase: [],
        jitter: 0,
        bedDrift: 0,
        tapBody: 0.34,
        tapKnocks: []
    )

    static let melodic = HapticProfile(
        id: .melodic,
        name: "Melodic",
        blurb: "Even, musical steps. The texture walks a scale as you move.",
        symbol: "waveform.path",
        intensity: 0.74,
        sharpness: 0.85,
        grainSpacing: 9,
        grainInterval: 0.055,
        // Evenly spaced steps up and back down — a consonant line.
        phrase: [0.18, 0.34, 0.50, 0.66, 0.82, 0.66, 0.50, 0.34],
        jitter: 0,
        bedDrift: 0,
        tapBody: 0.22,
        tapKnocks: [
            Knock(time: 0.075, intensity: 0.72, sharpness: 0.55),
            Knock(time: 0.150, intensity: 0.66, sharpness: 0.75),
            Knock(time: 0.225, intensity: 0.60, sharpness: 0.95)
        ]
    )

    static let discordant = HapticProfile(
        id: .discordant,
        name: "Off-key",
        blurb: "Deliberately incoherent. Nothing lines up and it never repeats.",
        symbol: "waveform.path.badge.minus",
        intensity: 0.82,
        sharpness: 0.78,
        grainSpacing: 9,
        grainInterval: 0.028,
        // Same mechanism as Melodic, but the steps lurch instead of climbing.
        phrase: [0.14, 0.71, 0.26, 0.93, 0.31, 0.58, 0.09, 0.99],
        jitter: 0.60,
        bedDrift: 0.55,
        tapBody: 0.20,
        // Uneven offsets and mismatched sharpness, so the tap never resolves.
        tapKnocks: [
            Knock(time: 0.038, intensity: 0.55, sharpness: 0.20),
            Knock(time: 0.121, intensity: 0.85, sharpness: 0.95),
            Knock(time: 0.163, intensity: 0.40, sharpness: 0.45)
        ]
    )

    static let all: [HapticProfile] = [.aggressive, .smooth, .melodic, .discordant]

    /// What a fresh install feels like. Aggressive, so the first thing anyone does
    /// with the app lands at full force rather than politely.
    static let fallback: HapticProfile = .aggressive

    static func profile(for kind: Kind) -> HapticProfile {
        all.first { $0.id == kind } ?? fallback
    }
}
