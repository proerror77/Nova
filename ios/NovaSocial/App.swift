import SwiftUI

@main
struct IceredApp: App {
    // App 持有全局认证状态，并下发 EnvironmentObject
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @State private var currentPage: AppPage

    // 监听 App 生命周期状态
    @Environment(\.scenePhase) private var scenePhase
    // 记录进入后台的时间戳
    @State private var backgroundEntryTime: Date?
    // 后台超时时间（2分钟）
    private let backgroundTimeout: TimeInterval = 120

    // Check if running in UI testing mode
    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    init() {
        // Reset auth state and skip to login when running UI tests
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            // CRITICAL: Clear isAuthenticated synchronously to prevent race condition
            // The view renders before async logout() completes, so we must set this first
            AuthenticationManager.shared.isAuthenticated = false
            // Then run full async cleanup (clears keychain, tokens, etc.)
            Task { await AuthenticationManager.shared.logout() }
            // Start directly on login page for UI tests
            _currentPage = State(initialValue: .login)
        } else {
            _currentPage = State(initialValue: .splash)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Splash Screen 优先显示（无论是否已登录）
                if currentPage == .splash {
                    SplashScreenView(currentPage: $currentPage)
                        .transition(.identity)
                }
                // Check authentication state
                else if !authManager.isAuthenticated {
                    // 未登录时的页面切换
                    switch currentPage {
                    case .welcome:
                        WelcomeView(currentPage: $currentPage)
                            .transition(.identity)
                    case .login:
                        LoginView(currentPage: $currentPage)
                            .transition(.identity)
                    case .forgotPassword:
                        ForgotPasswordView(currentPage: $currentPage)
                            .transition(.identity)
                    case .emailSentConfirmation(let email):
                        EmailSentConfirmationView(currentPage: $currentPage, email: email)
                            .transition(.identity)
                    case .resetPassword(let token):
                        ResetPasswordView(currentPage: $currentPage, resetToken: token)
                            .transition(.identity)
                    case .createAccount:
                        CreateAccountView(currentPage: $currentPage)
                            .transition(.identity)
                    case .phoneRegistration:
                        PhoneRegistrationView(currentPage: $currentPage)
                            .transition(.identity)
                    case .home:
                        // Skip 跳过登录直接进入Home
                        HomeView(currentPage: $currentPage)
                            .transition(.identity)
                    default:
                        LoginView(currentPage: $currentPage)
                            .transition(.identity)
                    }
                } else {
                    // 已登录后的页面切换
                    switch currentPage {
                    case .login, .createAccount, .welcome:
                        // 登录成功后跳转到首页
                        HomeView(currentPage: $currentPage)
                            .transition(.identity)
                            .onAppear { currentPage = .home }
                    case .home:
                        HomeView(currentPage: $currentPage)
                            .transition(.identity)
                    case .rankingList:
                        RankingListView(currentPage: $currentPage)
                            .transition(.identity)
                    case .message:
                        MessageView(currentPage: $currentPage)
                            .transition(.identity)
                    case .account:
                        ProfileView(currentPage: $currentPage)
                            .transition(.identity)
                    case .alice:
                        AliceView(currentPage: $currentPage)
                            .transition(.identity)
                    case .setting:
                        SettingsView(currentPage: $currentPage)
                            .transition(.identity)
                    case .profileSetting:
                        ProfileSettingView(currentPage: $currentPage)
                            .transition(.identity)
                    case .aliasName:
                        AliasNameView(currentPage: $currentPage)
                            .transition(.identity)
                    case .devices:
                        DevicesView(currentPage: $currentPage)
                            .transition(.identity)
                    case .inviteFriends:
                        InviteFriendsView(currentPage: $currentPage)
                            .transition(.identity)
                    case .myChannels:
                        MyChannelsView(currentPage: $currentPage)
                            .transition(.identity)
                    case .addFriends:
                        AddFriendsView(currentPage: $currentPage)
                            .transition(.identity)
                    case .newChat:
                        NewChatView(currentPage: $currentPage)
                            .transition(.identity)
                    case .getVerified:
                        GetVerifiedView(currentPage: $currentPage)
                            .transition(.identity)
                    default:
                        HomeView(currentPage: $currentPage)
                            .transition(.identity)
                    }
                }
            }
            .animation(.none, value: currentPage)
            .environmentObject(authManager)
            .environmentObject(themeManager)
            .preferredColorScheme(themeManager.colorScheme)
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // 当 App 进入后台时，记录时间戳
                if newPhase == .background {
                    backgroundEntryTime = Date()
                }
                // 当 App 从后台返回到活跃状态时，检查是否超过2分钟
                if newPhase == .active, let entryTime = backgroundEntryTime {
                    let timeInBackground = Date().timeIntervalSince(entryTime)
                    // 只有超过2分钟才显示 Splash Screen
                    if timeInBackground >= backgroundTimeout {
                        currentPage = .splash
                    }
                    // 重置时间戳
                    backgroundEntryTime = nil
                }
            }
        }
    }

    // MARK: - Deep Link Handler

    /// Handle deep links for password reset and other app navigation
    /// Supported URL formats:
    /// - nova://reset-password?token=xxx
    /// - icered://reset-password?token=xxx
    /// - https://app.nova.dev/reset-password?token=xxx
    private func handleDeepLink(_ url: URL) {
        #if DEBUG
        print("[DeepLink] Received URL: \(url)")
        #endif

        // Extract the path from different URL schemes
        let path: String
        if url.scheme == "https" {
            path = url.path
        } else {
            // For custom schemes like nova:// or icered://
            path = url.host ?? ""
        }

        // Handle reset-password deep link
        if path == "reset-password" || path == "/reset-password" {
            // Extract token from query parameters
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
               let queryItems = components.queryItems,
               let token = queryItems.first(where: { $0.name == "token" })?.value,
               !token.isEmpty {
                #if DEBUG
                print("[DeepLink] Password reset token received")
                #endif
                currentPage = .resetPassword(token: token)
            } else {
                #if DEBUG
                print("[DeepLink] No valid token in reset-password URL")
                #endif
                // Show error or redirect to forgot password
                currentPage = .forgotPassword
            }
        }
    }
}
