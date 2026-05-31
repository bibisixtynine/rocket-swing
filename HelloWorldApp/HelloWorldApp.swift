import SwiftUI

@main
struct HelloWorldApp: App {
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
