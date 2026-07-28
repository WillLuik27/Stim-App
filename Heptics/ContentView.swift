import SwiftUI

struct ContentView: View {

    @StateObject private var controller = OrbController()
    @StateObject private var prefs = Preferences()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            background
            OrbView(controller: controller)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged(controller.dragChanged)
                        .onEnded(controller.dragEnded)
                )
            settingsButton
            flashOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: controller.onAppear)
        .onDisappear(perform: controller.onDisappear)
        .sheet(isPresented: $showSettings) {
            SettingsView(prefs: prefs)
        }
    }

    /// A blank field — nothing but the orb. A whisper of a glow lifts behind it
    /// as it moves, too faint to read as an element in its own right.
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
            }
            Spacer()
        }
        .padding(.trailing, 6)
        // Gets out of the way while the orb is in use.
        .opacity(controller.isDragging ? 0 : 1)
        .animation(.easeOut(duration: 0.25), value: controller.isDragging)
    }

    /// Sits above everything, including the orb, so a tap blows the whole screen
    /// out to colour. Hit testing is off so it can never swallow a gesture.
    private var flashOverlay: some View {
        prefs.flashColor
            .ignoresSafeArea()
            .opacity(controller.flash)
            .allowsHitTesting(false)
    }
}

#Preview {
    ContentView().preferredColorScheme(.dark)
}
