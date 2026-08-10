import SwiftUI

struct SettingsView: View {

    @ObservedObject var prefs: Preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.height(620), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(white: 0.07))
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                section("Feel") {
                    feelRow
                }

                section("Flash") {
                    VStack(spacing: 11) {
                        flashSwitch

                        HStack(spacing: 12) {
                            whiteSwatch
                            SpectrumSlider(
                                hue: $prefs.flashHue,
                                isActive: !prefs.flashUsesWhite,
                                onScrub: {
                                    // Guarded: this runs every frame of the drag,
                                    // and the setter writes to UserDefaults.
                                    if prefs.flashUsesWhite { prefs.flashUsesWhite = false }
                                },
                                onCommit: {
                                    Haptics.shared.transient(intensity: 0.5, sharpness: 0.7)
                                }
                            )
                        }
                        // There is no colour to pick when nothing flashes, so the
                        // picker fades back rather than sitting there live.
                        .opacity(prefs.flashEnabled ? 1 : 0.25)
                        .disabled(!prefs.flashEnabled)
                        .animation(.easeOut(duration: 0.2), value: prefs.flashEnabled)
                    }
                }
            }
            .padding(22)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.32))
            content()
        }
    }

    /// The whole feel picker now lives one page over. This row shows the active
    /// feel's name and icon and navigates into `FeelView` to change it. Saving a
    /// Custom feel there dismisses the whole sheet back to the orb.
    private var feelRow: some View {
        let active = HapticProfile.profile(for: prefs.profileKind)
        let name = prefs.profileKind == .custom ? "Custom" : active.name
        let symbol = prefs.profileKind == .custom ? "slider.horizontal.3" : active.symbol
        return NavigationLink {
            FeelView(prefs: prefs, dismissToOrb: { dismiss() })
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Change feel")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(name)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// The flash's on/off switch, in the same card as the feel row above it.
    ///
    /// Worth having its own line rather than being folded into the colour picker
    /// as a "none" swatch: turning the flashing off is an accessibility choice,
    /// and it should read as one instead of hiding among the colours.
    private var flashSwitch: some View {
        Toggle(isOn: $prefs.flashEnabled) {
            HStack(spacing: 14) {
                Image(systemName: prefs.flashEnabled ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Flash on tap")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Lights the whole screen when you tap the orb.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // Grey rather than the system green, which would be the one piece of
        // colour in an otherwise monochrome app.
        .tint(Color(white: 0.5))
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .onChange(of: prefs.flashEnabled) { _, _ in
            Haptics.shared.transient(intensity: 0.5, sharpness: 0.7)
        }
    }

    private var whiteSwatch: some View {
        Button {
            prefs.flashUsesWhite = true
            Haptics.shared.transient(intensity: 0.5, sharpness: 0.7)
        } label: {
            Circle()
                .fill(.white)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(prefs.flashUsesWhite ? 0.9 : 0), lineWidth: 2)
                        .padding(-4)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: prefs.flashUsesWhite)
    }
}

/// A continuous rainbow the flash colour is picked from.
private struct SpectrumSlider: View {

    @Binding var hue: Double
    var isActive: Bool
    /// Every frame of the drag. Keep this cheap.
    var onScrub: () -> Void
    /// Once, on release. Safe place for a haptic.
    var onCommit: () -> Void

    /// Enough stops that the gradient reads as a smooth spectrum rather than as
    /// a handful of blended bands.
    private static let spectrum: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 24.0)
        .map { Color(hue: $0, saturation: 1, brightness: 1) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knob: CGFloat = 26

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: Self.spectrum,
                                         startPoint: .leading,
                                         endPoint: .trailing))

                Circle()
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                    // Dimmed rather than hidden while White is active, so the bar
                    // still reads as something you can grab.
                    .opacity(isActive ? 1 : 0.35)
                    // Inset so the knob stays fully on the bar at both ends.
                    .offset(x: (width - knob) * hue)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hue = min(max(value.location.x / max(width, 1), 0), 0.9999)
                        onScrub()
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: 32)
    }
}
