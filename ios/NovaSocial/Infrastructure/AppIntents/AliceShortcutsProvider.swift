import AppIntents

// MARK: - Alice Shortcuts Provider
/// Exposes Alice-related shortcuts to the system
/// These shortcuts appear in:
/// - Settings > Action Button (iPhone 15 Pro+)
/// - Shortcuts app
/// - Siri voice commands
@available(iOS 16.0, *)
struct AliceShortcutsProvider: AppShortcutsProvider {

    /// App shortcuts exposed to the system
    /// Apple recommends 2-5 key shortcuts per app
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WakeAliceVoiceModeIntent(),
            phrases: [
                // English phrases - all must contain \(.applicationName)
                "Talk to Alice in \(.applicationName)",
                "Start voice mode in \(.applicationName)",
                "Wake Alice in \(.applicationName)",
                "Open \(.applicationName) voice chat",
                // Chinese phrases - all must contain \(.applicationName)
                "在 \(.applicationName) 叫醒 Alice",
                "開啟 \(.applicationName) 語音",
                "用 \(.applicationName) 和 Alice 說話"
            ],
            shortTitle: "Alice Voice",
            systemImageName: "waveform"
        )
    }
}
