import Foundation

@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - Theme Settings
    var isDarkMode = false
    var isSavingDarkMode = false

    // MARK: - Account Management
    var accounts: [Account] = []
    var currentAccountId: String?
    var isLoadingAccounts = false
    var isSwitchingAccount = false
    var hasLoadedAccounts = false  // 标记是否已完成首次加载

    // MARK: - General State
    var isLoading = false
    var userSettings: UserSettings?
    var errorMessage: String?

    // MARK: - Dependencies
    private let authManager: AuthenticationManager
    private let userService: UserService
    private let themeManager: ThemeManager
    private let accountsService: AccountsService

    // MARK: - Computed Properties

    /// The primary (main) account
    var primaryAccount: Account? {
        accounts.first { $0.isPrimary }
    }

    /// Alias accounts (non-primary)
    var aliasAccounts: [Account] {
        accounts.filter { $0.isAlias }
    }

    /// Currently active account
    var currentAccount: Account? {
        guard let id = currentAccountId else { return nil }
        return accounts.first { $0.id == id }
    }

    /// Check if user has any alias accounts
    var hasAliasAccount: Bool {
        !aliasAccounts.isEmpty
    }

    /// Current logged-in user profile (for display purposes)
    var currentUser: UserProfile? {
        authManager.currentUser
    }

    // MARK: - Initialization

    init(
        authManager: AuthenticationManager? = nil,
        userService: UserService? = nil,
        themeManager: ThemeManager? = nil,
        accountsService: AccountsService? = nil
    ) {
        self.authManager = authManager ?? AuthenticationManager.shared
        self.userService = userService ?? UserService.shared
        self.themeManager = themeManager ?? ThemeManager.shared
        self.accountsService = accountsService ?? AccountsService.shared
        self.isDarkMode = self.themeManager.isDarkMode
    }

    // MARK: - Lifecycle

    func onAppear() {
        isDarkMode = themeManager.isDarkMode
        Task {
            await loadAccounts()
        }
    }

    func loadSettings() async {
        isLoading = true
        errorMessage = nil
        isDarkMode = themeManager.isDarkMode
        await loadAccounts()
        isLoading = false
    }

    // MARK: - Account Management

    /// Load all accounts for the current user
    func loadAccounts() async {
        isLoadingAccounts = true
        errorMessage = nil

        do {
            let response = try await accountsService.getAccounts()
            accounts = response.accounts
            currentAccountId = response.currentAccountId

            #if DEBUG
            print("[SettingsViewModel] Loaded \(accounts.count) accounts, current: \(currentAccountId ?? "none")")
            #endif
        } catch {
            #if DEBUG
            print("[SettingsViewModel] Failed to load accounts: \(error)")
            #endif
            // Don't show error to user - accounts feature may not be available
            // Just use empty state
            accounts = []
        }

        hasLoadedAccounts = true  // 标记已完成加载（无论成功或失败）
        isLoadingAccounts = false
    }

    /// Switch to a different account
    /// - Parameter account: The account to switch to
    func switchAccount(to account: Account) async {
        guard account.id != currentAccountId else { return }

        isSwitchingAccount = true
        errorMessage = nil

        do {
            let response = try await accountsService.switchAccount(accountId: account.id)

            // Update auth tokens
            await authManager.updateTokens(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken
            )

            // Update current account
            currentAccountId = account.id

            // Reload accounts to get fresh data
            await loadAccounts()

            #if DEBUG
            print("[SettingsViewModel] Switched to account: \(account.effectiveDisplayName)")
            #endif
        } catch {
            errorMessage = NSLocalizedString("Failed to switch account", comment: "")
            #if DEBUG
            print("[SettingsViewModel] Failed to switch account: \(error)")
            #endif
        }

        isSwitchingAccount = false
    }

    /// Navigate to edit an alias account
    /// - Parameter account: The alias account to edit
    func editAliasAccount(_ account: Account) {
        AliasEditState.shared.startEditing(account: account)
    }

    /// Create a new alias account (navigates to alias creation)
    func createNewAliasAccount() {
        AliasEditState.shared.clearEditingState()
    }

    // MARK: - Theme Settings

    func updateDarkMode(enabled: Bool) async {
        isSavingDarkMode = true
        errorMessage = nil
        themeManager.apply(isDarkMode: enabled)
        isSavingDarkMode = false
    }

    // MARK: - Logout

    func logout() async {
        await authManager.logout()
    }

}
