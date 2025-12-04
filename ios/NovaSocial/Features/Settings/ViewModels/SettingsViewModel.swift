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
    private let themeManager: ThemeManager

    init(
        authManager: AuthenticationManager? = nil,
        userService: UserService? = nil,
        themeManager: ThemeManager? = nil
    ) {
        self.authManager = authManager ?? AuthenticationManager.shared
        self.userService = userService ?? UserService.shared
        self.themeManager = themeManager ?? ThemeManager.shared
        self.isDarkMode = self.themeManager.isDarkMode
    }

    func onAppear() {
        // 對於 iOS UI，深色模式只需讀取本機 ThemeManager 狀態，
        // 不強依賴後端設定。
        isDarkMode = themeManager.isDarkMode
    }

    func loadSettings() async {
        // 保留函式簽名給未來擴充使用，但目前深色模式偏好只依賴本機 ThemeManager。
        isLoading = true
        errorMessage = nil
        isDarkMode = themeManager.isDarkMode
        isLoading = false
    }

    func updateDarkMode(enabled: Bool) async {
        isSavingDarkMode = true
        errorMessage = nil

        // iOS UI 只需要調整 App 本身的顏色模式，不需要依賴後端。
        themeManager.apply(isDarkMode: enabled)

        isSavingDarkMode = false
    }

    func logout() async {
        await authManager.logout()
    }
}
