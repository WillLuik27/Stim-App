import SwiftUI

struct ContentView: View {

    @StateObject private var controller = OrbController()
    @StateObject private var prefs = Preferences()
    @State private var showSettings = false
    /// Where the gear sits, so the touch sheet can leave a hole for it.
    @State private var gearFrame: CGRect = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background
                OrbView(controller: controller)
                MultiTouchLayer(
                    passthrough: gearFrame,
                    onBegan: controller.touchBegan(id:at:),
                    onMoved: controller.touchMoved(id:to:),
                    onEnded: controller.touchEnded(id:)
                )
                settingsButton
                flashOverlay
            }
            .coordinateSpace(name: Self.field)
            .onAppear {
                controller.setBounds(geometry.size)
                controller.onAppear()
            }
            .onChange(of: geometry.size) { _, size in
                controller.setBounds(size)
            }
        }
        .ignoresSafeArea()
        .onDisappear(perform: controller.onDisappear)
        // Captures the binding rather than the view, so the callback doesn't have
        // to reach back into a non-sendable `self`.
        .onPreferenceChange(GearFrameKey.self) { [$gearFrame] frame in
            $gearFrame.wrappedValue = frame
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(prefs: prefs)
        }
    }

    /// The coordinate space the goo, the touches and the gear all agree on.
    private static let field = "field"

    /// A blank field — nothing but the goo. A whisper of a glow lifts behind it as
    /// it moves, too faint to read as an element in its own right.
    private var background: some View {
        ZStack {
            Color(white: 0.035)

            RadialGradient(
                colors: [
                    Color(white: 0.16).opacity(controller.speed * 0.5 + controller.pull * 0.18),
                    .clear
                ],
                center: .center,
                startRadius: 8,
                endRadius: 300
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var settingsButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    Haptics.shared.transient(intensity: 0.4, sharpness: 0.6)
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: GearFrameKey.self,
                            // Generous, so a thumb aiming at the gear never lands
                            // in the goo instead.
                            value: proxy.frame(in: .named(Self.field)).insetBy(dx: -8, dy: -8)
                        )
                    }
                )
            }
            Spacer()
        }
        .padding(.top, 52)
        .padding(.trailing, 6)
        // Gets out of the way while the goo is in use.
        .opacity(controller.isDragging ? 0 : 1)
        .animation(.easeOut(duration: 0.25), value: controller.isDragging)
    }

    /// Sits above everything, including the goo, so a tap blows the whole screen
    /// out to colour. Hit testing is off so it can never swallow a gesture.
    private var flashOverlay: some View {
        prefs.flashColor
            .ignoresSafeArea()
            .opacity(controller.flash)
            .allowsHitTesting(false)
    }
}

/// Carries the gear button's frame back up to the touch sheet.
private struct GearFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

#Preview {
    ContentView().preferredColorScheme(.dark)
}
