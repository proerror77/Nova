import AppIntents
import Foundation

// MARK: - Notification Name Extension
extension Notification.Name {
    static let openAliceVoiceMode = Notification.Name("OpenAliceVoiceMode")
}

// MARK: - Voice Mode Intent Keys (App Groups)
enum VoiceModeIntentKeys {
    static let appGroupSuiteName = "group.com.app.icered.pro"
    static let shouldOpenVoiceMode = "intent.shouldOpenVoiceMode"
    static let voiceModeTimestamp = "intent.voiceModeTimestamp"
}

// MARK: - Wake Alice Voice Mode Intent
/// App Intent that can be assigned to iPhone Action Button (iPhone 15 Pro+)
/// Allows users to instantly start a voice conversation with Alice AI
@available(iOS 16.0, *)
struct WakeAliceVoiceModeIntent: AppIntent {

    static var title: LocalizedStringResource = "Wake Alice Voice Mode"

    static var description = IntentDescription("Start a voice conversation with Alice AI")

    /// Opens app in foreground when triggered from Action Button
    static var openAppWhenRun: Bool = true

    /// Perform the intent action
    @MainActor
    func perform() async throws -> some IntentResult {
        // Use App Groups UserDefaults to communicate with main app
        // NotificationCenter doesn't work across processes
        if let defaults = UserDefaults(suiteName: VoiceModeIntentKeys.appGroupSuiteName) {
            defaults.set(true, forKey: VoiceModeIntentKeys.shouldOpenVoiceMode)
            defaults.set(Date().timeIntervalSince1970, forKey: VoiceModeIntentKeys.voiceModeTimestamp)
            defaults.synchronize()
        }

        #if DEBUG
        print("[WakeAliceVoiceModeIntent] Intent triggered - flag set in App Groups UserDefaults")
        #endif

        return .result()
    }
}
