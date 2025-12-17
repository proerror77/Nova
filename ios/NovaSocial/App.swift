import SwiftUI

@main
struct IceredApp: App {
    // Connect AppDelegate for push notifications
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // App 持有全局认证状态，并下发 EnvironmentObject
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var pushManager = PushNotificationManager.shared
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
                    case .phoneLogin:
                        PhoneLoginView(currentPage: $currentPage)
                            .transition(.identity)
                    case .phoneRegistration:
                        PhoneRegistrationView(currentPage: $currentPage)
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
            .environmentObject(pushManager)
            .preferredColorScheme(themeManager.colorScheme)
            .task {
                // Check notification settings on app launch
                await pushManager.checkNotificationSettings()
                await initializeMatrixBridgeIfNeeded()
            }
            .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                // Request push notification permission when user logs in
                if isAuthenticated {
                    Task {
                        await pushManager.requestAuthorization()
                        await initializeMatrixBridgeIfNeeded()
                    }
                } else {
                    // Unregister push token on logout
                    Task {
                        await pushManager.unregisterToken()
                        await MatrixBridgeService.shared.shutdown(clearCredentials: true)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PushNotificationReceived"))) { notification in
                // Handle push notification navigation
                handlePushNotification(notification.userInfo)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { notification in
                // Handle session expiration - navigate to login immediately
                handleSessionExpired(notification.userInfo)
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // 当 App 进入后台时，记录时间戳
                if newPhase == .background {
                    backgroundEntryTime = Date()
                    print("[App] 📱 App entered background")
                }
                // 当 App 从后台返回到活跃状态时
                if newPhase == .active, let entryTime = backgroundEntryTime {
                    let timeInBackground = Date().timeIntervalSince(entryTime)
                    print("[App] 📱 App returned to foreground after \(String(format: "%.1f", timeInBackground))s")
                    
                    // 只有超过2分钟才显示 Splash Screen (with full re-validation)
                    if timeInBackground >= backgroundTimeout {
                        print("[App] ⏰ Background timeout exceeded, showing splash screen")
                        currentPage = .splash
                    } else if authManager.isAuthenticated && timeInBackground >= 30 {
                        // For shorter background periods (30s+), silently validate session
                        // This catches token expiration without showing splash
                        print("[App] 🔍 Validating session after \(String(format: "%.0f", timeInBackground))s in background")
                        Task {
                            let isValid = await authManager.validateSession()
                            if !isValid {
                                print("[App] ❌ Session invalid after background, navigating to login")
                                currentPage = .login
                            }
                        }
                    }
                    // 重置时间戳
                    backgroundEntryTime = nil
                }
            }
        }
    }

    // MARK: - Push Notification Handling

    /// Handle push notification navigation based on notification type
    private func handlePushNotification(_ userInfo: [AnyHashable: Any]?) {
        guard let userInfo = userInfo,
              let type = userInfo["type"] as? String else {
            return
        }

        // Ensure user is authenticated before navigating
        guard authManager.isAuthenticated else { return }

        // Navigate based on notification type
        switch type {
        case "like", "comment", "mention", "share", "reply":
            // Navigate to the related post if available
            if userInfo["post_id"] != nil {
                // TODO: Navigate to post detail view
                // For now, just go to home
                currentPage = .home
            }
        case "follow":
            // Navigate to the follower's profile
            if userInfo["user_id"] != nil {
                // TODO: Navigate to user profile view
                currentPage = .home
            }
        case "message":
            // Navigate to messages
            currentPage = .message
        default:
            // Default to home
            currentPage = .home
        }
    }
    
    // MARK: - Session Expiration Handling
    
    /// Handle session expiration - immediately navigate to login
    private func handleSessionExpired(_ userInfo: [AnyHashable: Any]?) {
        print("╔════════════════════════════════════════════════════════════")
        print("║ [App] 🚨 SESSION EXPIRED NOTIFICATION RECEIVED")
        print("╚════════════════════════════════════════════════════════════")
        
        // Extract expiration reason if available
        if let reason = userInfo?["reason"] as? SessionExpiredReason {
            print("[App] Expiration reason: \(reason.rawValue)")
            print("[App] User message: \(reason.userMessage)")
        }
        
        // Navigate to login page immediately
        print("[App] 🔄 Navigating to login page...")
        currentPage = .login
        
        // Show alert to user (optional - the login page should handle this)
        // The sessionState and lastExpirationReason on authManager can be used
        // by LoginView to show an appropriate message
    }

    @MainActor
    private func initializeMatrixBridgeIfNeeded() async {
        guard !isUITesting else { return }
        guard authManager.isAuthenticated, !authManager.isGuestMode else { return }

        do {
            try await MatrixBridgeService.shared.initialize()
        } catch {
            #if DEBUG
            print("[App] Matrix initialization failed: \(error)")
            #endif
        }
    }
}
