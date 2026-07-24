import SwiftUI

/// User-facing settings, persisted across launches.
final class Preferences: ObservableObject {

    @Published var profileKind: HapticProfile.Kind {
        didSet {
            Haptics.shared.profile = HapticProfile.profile(for: profileKind)
            defaults.set(profileKind.rawValue, forKey: Keys.profile)
        }
    }

    /// White is its own mode rather than a saturation of zero, so picking a hue
    /// and going back to white doesn't lose the hue you had.
    @Published var flashUsesWhite: Bool {
        didSet { defaults.set(flashUsesWhite, forKey: Keys.flashWhite) }
    }

    /// 0...1 around the colour wheel.
    @Published var flashHue: Double {
        didSet { defaults.set(flashHue, forKey: Keys.flashHue) }
    }

    var profile: HapticProfile { HapticProfile.profile(for: profileKind) }

    var flashColor: Color {
        flashUsesWhite ? .white : Color(hue: flashHue, saturation: 1, brightness: 1)
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let profile = "hapticProfile"
        static let flashWhite = "flashUsesWhite"
        static let flashHue = "flashHue"
    }

    init() {
        let saved = defaults.string(forKey: Keys.profile).flatMap(HapticProfile.Kind.init(rawValue:))
        profileKind = saved ?? .smooth
        flashUsesWhite = defaults.object(forKey: Keys.flashWhite) as? Bool ?? true
        flashHue = defaults.object(forKey: Keys.flashHue) as? Double ?? 0.55

        // `didSet` doesn't run during init, so push the loaded profile through by hand.
        Haptics.shared.profile = HapticProfile.profile(for: profileKind)
    }
}
