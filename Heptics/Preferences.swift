import SwiftUI

/// Shape of the movement texture's pitch line for a custom tuning.
enum CustomMelody: String, CaseIterable, Identifiable {
    case none, scale, wild
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .scale: return "Scale"
        case .wild: return "Wild"
        }
    }
}

/// User-facing settings, persisted across launches.
final class Preferences: ObservableObject {

    @Published var profileKind: HapticProfile.Kind {
        didSet {
            Haptics.shared.profile = profile
            defaults.set(profileKind.rawValue, forKey: Keys.profile)
        }
    }

    // MARK: - Flash

    /// White is its own mode rather than a saturation of zero, so picking a hue
    /// and going back to white doesn't lose the hue you had.
    @Published var flashUsesWhite: Bool {
        didSet { defaults.set(flashUsesWhite, forKey: Keys.flashWhite) }
    }

    /// 0...1 around the colour wheel.
    @Published var flashHue: Double {
        didSet { defaults.set(flashHue, forKey: Keys.flashHue) }
    }

    // MARK: - Custom tuning
    //
    // These are the same knobs the four presets are built from, exposed one-to-one
    // so the end user can dial their own feel. Each is stored as a Double/Int for
    // easy slider/stepper binding and converted when the profile is assembled.
    // Every setter persists and — if Custom is the active feel — pushes the change
    // to the live engine so edits are felt immediately.

    @Published var customIntensity: Double { didSet { save(customIntensity, Keys.cIntensity); applyIfCustom() } }
    @Published var customSharpness: Double { didSet { save(customSharpness, Keys.cSharpness); applyIfCustom() } }
    @Published var customGrainSpacing: Double { didSet { save(customGrainSpacing, Keys.cGrainSpacing); applyIfCustom() } }
    @Published var customGrainInterval: Double { didSet { save(customGrainInterval, Keys.cGrainInterval); applyIfCustom() } }
    @Published var customJitter: Double { didSet { save(customJitter, Keys.cJitter); applyIfCustom() } }
    @Published var customBedDrift: Double { didSet { save(customBedDrift, Keys.cBedDrift); applyIfCustom() } }
    @Published var customTapBody: Double { didSet { save(customTapBody, Keys.cTapBody); applyIfCustom() } }
    @Published var customTapKnocks: Int { didSet { save(Double(customTapKnocks), Keys.cTapKnocks); applyIfCustom() } }
    @Published var customMelodySteps: Int { didSet { save(Double(customMelodySteps), Keys.cMelodySteps); applyIfCustom() } }
    @Published var customMelody: CustomMelody {
        didSet { defaults.set(customMelody.rawValue, forKey: Keys.cMelody); applyIfCustom() }
    }

    /// Sensible mid-range starting point for a fresh custom tuning.
    enum CustomDefaults {
        static let intensity = 0.70, sharpness = 0.60
        static let grainSpacing = 9.0, grainInterval = 0.030
        static let jitter = 0.10, bedDrift = 0.0, tapBody = 0.20
        static let tapKnocks = 1, melodySteps = 6
        static let melody = CustomMelody.none
    }

    // MARK: - Derived

    /// The active feel, resolving Custom to the user's own parameters.
    var profile: HapticProfile {
        profileKind == .custom ? customProfile : HapticProfile.profile(for: profileKind)
    }

    /// A `HapticProfile` assembled live from the custom knobs.
    var customProfile: HapticProfile {
        HapticProfile(
            id: .custom,
            name: "Custom",
            blurb: "Your own tuning.",
            symbol: "slider.horizontal.3",
            intensity: Float(customIntensity),
            sharpness: Float(customSharpness),
            grainSpacing: CGFloat(customGrainSpacing),
            grainInterval: customGrainInterval,
            phrase: customPhrase,
            jitter: Float(customJitter),
            bedDrift: Float(customBedDrift),
            tapBody: customTapBody,
            tapKnocks: customTapKnocksList
        )
    }

    var flashColor: Color {
        flashUsesWhite ? .white : Color(hue: flashHue, saturation: 1, brightness: 1)
    }

    /// Restore the custom tuning to its defaults.
    func resetCustom() {
        customIntensity = CustomDefaults.intensity
        customSharpness = CustomDefaults.sharpness
        customGrainSpacing = CustomDefaults.grainSpacing
        customGrainInterval = CustomDefaults.grainInterval
        customJitter = CustomDefaults.jitter
        customBedDrift = CustomDefaults.bedDrift
        customTapBody = CustomDefaults.tapBody
        customTapKnocks = CustomDefaults.tapKnocks
        customMelodySteps = CustomDefaults.melodySteps
        customMelody = CustomDefaults.melody
    }

    // MARK: - Phrase / knock generation

    /// Builds the sharpness line from the melody shape and step count. A `scale`
    /// is a triangle wave — up then down — so it loops without a jarring reset; a
    /// `wild` line is that same set of steps deterministically shuffled, so it's
    /// still bounded but never resolves.
    private var customPhrase: [Float] {
        guard customMelody != .none, customMelodySteps >= 2 else { return [] }
        let n = customMelodySteps
        let lo: Float = 0.15, hi: Float = 0.85
        var values = (0..<n).map { i -> Float in
            let t = Float(i) / Float(n)
            let triangle = t < 0.5 ? t * 2 : (1 - t) * 2
            return lo + (hi - lo) * triangle
        }
        if customMelody == .wild {
            var generator = SplitMix64(seed: 0x5EED)
            values.shuffle(using: &generator)
        }
        return values
    }

    /// Evenly spaced, decaying follow-up hits for the tap.
    private var customTapKnocksList: [HapticProfile.Knock] {
        guard customTapKnocks > 0 else { return [] }
        let intensities: [Float] = [0.85, 0.70, 0.58]
        return (0..<customTapKnocks).map { i in
            HapticProfile.Knock(time: 0.05 + Double(i) * 0.05,
                                intensity: intensities[min(i, intensities.count - 1)],
                                sharpness: 0.7)
        }
    }

    // MARK: - Plumbing

    private let defaults = UserDefaults.standard

    private func save(_ value: Double, _ key: String) { defaults.set(value, forKey: key) }

    /// Keep the running engine in step while the user drags a slider.
    private func applyIfCustom() {
        if profileKind == .custom { Haptics.shared.profile = customProfile }
    }

    private enum Keys {
        static let profile = "hapticProfile"
        static let flashWhite = "flashUsesWhite"
        static let flashHue = "flashHue"
        static let cIntensity = "customIntensity"
        static let cSharpness = "customSharpness"
        static let cGrainSpacing = "customGrainSpacing"
        static let cGrainInterval = "customGrainInterval"
        static let cJitter = "customJitter"
        static let cBedDrift = "customBedDrift"
        static let cTapBody = "customTapBody"
        static let cTapKnocks = "customTapKnocks"
        static let cMelodySteps = "customMelodySteps"
        static let cMelody = "customMelody"
    }

    init() {
        // Local reference so the helpers below don't touch `self` before every
        // stored property is initialized (which Swift forbids).
        let store = UserDefaults.standard

        let saved = store.string(forKey: Keys.profile).flatMap(HapticProfile.Kind.init(rawValue:))
        profileKind = saved ?? .smooth
        flashUsesWhite = store.object(forKey: Keys.flashWhite) as? Bool ?? true
        flashHue = store.object(forKey: Keys.flashHue) as? Double ?? 0.55

        // `object(forKey:)` is nil the first run, so fall back to the defaults.
        func d(_ key: String, _ fallback: Double) -> Double {
            store.object(forKey: key) as? Double ?? fallback
        }
        customIntensity = d(Keys.cIntensity, CustomDefaults.intensity)
        customSharpness = d(Keys.cSharpness, CustomDefaults.sharpness)
        customGrainSpacing = d(Keys.cGrainSpacing, CustomDefaults.grainSpacing)
        customGrainInterval = d(Keys.cGrainInterval, CustomDefaults.grainInterval)
        customJitter = d(Keys.cJitter, CustomDefaults.jitter)
        customBedDrift = d(Keys.cBedDrift, CustomDefaults.bedDrift)
        customTapBody = d(Keys.cTapBody, CustomDefaults.tapBody)
        customTapKnocks = Int(d(Keys.cTapKnocks, Double(CustomDefaults.tapKnocks)))
        customMelodySteps = Int(d(Keys.cMelodySteps, Double(CustomDefaults.melodySteps)))
        customMelody = store.string(forKey: Keys.cMelody)
            .flatMap(CustomMelody.init(rawValue:)) ?? CustomDefaults.melody

        // `didSet` doesn't run during init, so push the loaded profile through by hand.
        Haptics.shared.profile = profile
    }
}

/// Small deterministic RNG so the "Wild" melody shuffle is stable across launches
/// rather than jumping around every time the profile is rebuilt.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
