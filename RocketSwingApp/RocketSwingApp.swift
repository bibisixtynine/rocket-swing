import SwiftUI

@main
struct RocketSwingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .statusBarHidden(true)
                .hiddenPersistentSystemOverlaysWhenAvailable()
        }
    }
}

extension View {
    @ViewBuilder
    func hiddenPersistentSystemOverlaysWhenAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self.persistentSystemOverlays(.hidden)
        } else {
            self
        }
    }
}
