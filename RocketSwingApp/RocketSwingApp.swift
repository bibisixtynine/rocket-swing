import SwiftUI

@main
struct RocketSwingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if !os(macOS)
                .statusBarHidden(true)
                #endif
                .hiddenPersistentSystemOverlaysWhenAvailable()
        }
    }
}

extension View {
    @ViewBuilder
    func hiddenPersistentSystemOverlaysWhenAvailable() -> some View {
        #if os(macOS)
        self
        #else
        if #available(iOS 16.0, *) {
            self.persistentSystemOverlays(.hidden)
        } else {
            self
        }
        #endif
    }
}
