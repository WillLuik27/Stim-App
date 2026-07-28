import SwiftUI

/// The feel picker, one page over from Settings. Lists the presets and, below
/// them, a link into the Custom editor.
///
/// Reached from the "Feel" row in `SettingsView`. `dismissToOrb` closes the whole
/// Settings sheet — it's handed down so the Custom editor's Save button can drop
/// the user straight back to the orb rather than just popping one screen.
struct FeelView: View {

    @ObservedObject var prefs: Preferences
    var dismissToOrb: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(HapticProfile.all) { profile in
                    profileRow(profile)
                }
                customRow
            }
            .padding(22)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(white: 0.07).ignoresSafeArea())
        .navigationTitle("Feel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(white: 0.07), for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private func profileRow(_ profile: HapticProfile) -> some View {
        let selected = prefs.profileKind == profile.id
        return Button {
            prefs.profileKind = profile.id
            // Play it immediately — the description only means so much.
            Haptics.shared.demo()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: profile.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? .white : .white.opacity(0.42))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? .white : .white.opacity(0.78))
                    Text(profile.blurb)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(selected ? 1 : 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.white.opacity(selected ? 0.10 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.white.opacity(selected ? 0.22 : 0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    /// Custom sits below the presets. It's a navigation link — tapping it opens
    /// the editor, which makes Custom the active feel on appear. The chevron and
    /// wording signal it goes somewhere, unlike the preset rows.
    private var customRow: some View {
        let selected = prefs.profileKind == .custom
        return NavigationLink {
            CustomTuningView(prefs: prefs, dismissToOrb: dismissToOrb)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? .white : .white.opacity(0.42))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Custom")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? .white : .white.opacity(0.78))
                    Text("Build your own feel — tune every setting.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.white.opacity(selected ? 0.10 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.white.opacity(selected ? 0.22 : 0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}
