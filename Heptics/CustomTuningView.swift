import SwiftUI

/// The build-your-own-feel editor. Every control maps one-to-one to a field the
/// four presets are made of, so the user is tuning the same machinery.
///
/// Opening this screen makes Custom the active feel, so every drag of a slider is
/// heard the moment you lift off (via `Preferences.applyIfCustom`). Nothing is
/// felt in the Simulator — use it on a device to judge a change.
struct CustomTuningView: View {

    @ObservedObject var prefs: Preferences
    /// Closes the whole Settings sheet, dropping the user back on the orb.
    var dismissToOrb: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                group("Strength") {
                    TuningSlider(title: "Intensity", value: $prefs.customIntensity,
                                 range: 0...1, onCommit: preview) { percent($0) }
                    TuningSlider(title: "Sharpness", value: $prefs.customSharpness,
                                 range: 0...1, onCommit: preview) { percent($0) }
                }

                group("Movement texture") {
                    TuningSlider(title: "Grain spacing", value: $prefs.customGrainSpacing,
                                 range: 3...20, onCommit: preview) { "\(Int($0.rounded())) pt" }
                    TuningSlider(title: "Min gap", value: $prefs.customGrainInterval,
                                 range: 0.012...0.08, onCommit: preview) { "\(Int(($0 * 1000).rounded())) ms" }
                }

                group("Character") {
                    TuningSlider(title: "Jitter", value: $prefs.customJitter,
                                 range: 0...1, onCommit: preview) { percent($0) }
                    TuningSlider(title: "Bed drift", value: $prefs.customBedDrift,
                                 range: 0...1, onCommit: preview) { percent($0) }
                }

                group("Melody") {
                    Picker("Melody", selection: $prefs.customMelody) {
                        ForEach(CustomMelody.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if prefs.customMelody != .none {
                        TuningStepper(title: "Steps", value: $prefs.customMelodySteps,
                                      range: 2...8, onCommit: preview)
                    }
                }

                group("Tap") {
                    TuningSlider(title: "Body length", value: $prefs.customTapBody,
                                 range: 0.10...0.40, onCommit: preview) { "\(Int(($0 * 1000).rounded())) ms" }
                    TuningStepper(title: "Extra knocks", value: $prefs.customTapKnocks,
                                  range: 0...3, onCommit: preview)
                }

                saveButton
                resetButton
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(white: 0.07).ignoresSafeArea())
        .navigationTitle("Custom")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(white: 0.07), for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            // Editing should be live and audible, so make Custom the active feel.
            if prefs.profileKind != .custom { prefs.profileKind = .custom }
        }
    }

    private var saveButton: some View {
        Button(action: dismissToOrb) {
            Label("Save", systemImage: "checkmark")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(.white))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var resetButton: some View {
        Button {
            prefs.resetCustom()
            preview()
        } label: {
            Text("Reset to defaults")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    /// Play the current tuning so a change can actually be judged.
    private func preview() {
        Haptics.shared.profile = prefs.customProfile
        Haptics.shared.demo()
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func group<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.32))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.white.opacity(0.045)))
    }
}

/// Label + live value readout + slider. `onCommit` fires on release only, so the
/// preview haptic never runs on the drag's hot path.
private struct TuningSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onCommit: () -> Void
    var format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(format(value))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Slider(value: $value, in: range) { editing in
                if !editing { onCommit() }
            }
            .tint(.white.opacity(0.85))
        }
    }
}

/// Label + value + −/+ stepper for the integer knobs.
private struct TuningStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var onCommit: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            // Own readout, so the value is actually visible. Leaving it as the
            // Stepper's label wouldn't work — .labelsHidden() would hide it.
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.trailing, 10)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: value)
            Stepper("", value: $value, in: range)
                .labelsHidden()
                .onChange(of: value) { _, _ in onCommit() }
                .fixedSize()
        }
    }
}
