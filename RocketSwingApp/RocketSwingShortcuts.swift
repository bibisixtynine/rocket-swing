import AppIntents

@available(iOS 16.0, *)
struct ShowRocketSwingIntent: AppIntent {
    static let title: LocalizedStringResource = "Afficher Rocket Swing"
    static let description = IntentDescription("Ouvre l'app Rocket Swing.")

    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 16.0, *)
struct RocketSwingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowRocketSwingIntent(),
            phrases: [
                "Afficher Rocket Swing dans \(.applicationName)",
                "Ouvrir Rocket Swing dans \(.applicationName)"
            ],
            shortTitle: "Rocket Swing",
            systemImageName: "sparkles"
        )
    }
}
