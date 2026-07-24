import SwiftUI

@main
struct HepticsApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Keep the screen awake so the orb stays usable in a pocket.
                UIApplication.shared.isIdleTimerDisabled = true
                Haptics.shared.start()
            case .inactive, .background:
                UIApplication.shared.isIdleTimerDisabled = false
                Haptics.shared.stop()
            @unknown default:
                break
            }
        }
    }
}
