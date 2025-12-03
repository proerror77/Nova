import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var isDarkMode = false
    @Published var isLoading = false
    @Published var isSavingDarkMode = false
    @Published var userSettings: UserSettings?
    @Published var errorMessage: String?

    private let authManager: AuthenticationManager
    private let userService: UserService

    init(
        authManager: AuthenticationManager? = nil,
        userService: UserService? = nil
    ) {
        self.authManager = authManager ?? AuthenticationManager.shared
        self.userService = userService ?? UserService.shared
    }

    func onAppear() {
        Task { await loadSettings() }
    }

    func loadSettings() async {
        guard let userId = authManager.currentUser?.id,
              !authManager.isGuestMode else { return }

        isLoading = true
        errorMessage = nil

        do {
            let settings = try await userService.getSettings(userId: userId)
            userSettings = settings
            isDarkMode = settings.safeDarkMode
        } catch {
            // Keep current state if loading fails
            errorMessage = NSLocalizedString("Failed to load settings", comment: "")
            #if DEBUG
            print("[Settings] Failed to load settings: \(error)")
            #endif
        }

        isLoading = false
    }

    func updateDarkMode(enabled: Bool) async {
        guard let userId = authManager.currentUser?.id,
              !authManager.isGuestMode else { return }

        isSavingDarkMode = true
        errorMessage = nil

        do {
            let updatedSettings = try await userService.updateDarkMode(userId: userId, enabled: enabled)
            userSettings = updatedSettings
        } catch {
            // Revert on failure
            isDarkMode = !enabled
            errorMessage = NSLocalizedString("Failed to update dark mode", comment: "")
            #if DEBUG
            print("[Settings] Failed to update dark mode: \(error)")
            #endif
        }

        isSavingDarkMode = false
    }

    func logout() async {
        await authManager.logout()
    }
}
