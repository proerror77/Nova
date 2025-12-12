import SwiftUI
import UserNotifications

@main
struct ICEREDApp: App {
    // Connect AppDelegate for push notification handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // App 持有全局认证状态，并下发 EnvironmentObject
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var pushManager = PushNotificationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @State private var currentPage: AppPage

    // 监听 App 生命周期状态
    @Environment(\.scenePhase) private var scenePhase
    // 记录 App 是否进入过后台
    @State private var hasEnteredBackground = false

    // Deep link state for password reset
    @State private var resetPasswordToken: String?
    @State private var showResetPasswordView = false

    // Matrix 初始化狀態
    @State private var isMatrixInitialized = false

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

        // 設置登入通知監聽器以初始化 Matrix
        setupMatrixInitialization()
    }

    // MARK: - Matrix Integration

    /// 設置 Matrix 初始化 - 在用戶登入後觸發
    private func setupMatrixInitialization() {
        // 監聽認證狀態變化
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UserDidLogin"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await initializeMatrixBridge()
            }
        }
    }

    /// 初始化 Matrix Bridge 服務
    @MainActor
    private func initializeMatrixBridge() async {
        guard !isMatrixInitialized else { return }

        #if DEBUG
        print("[App] 正在初始化 Matrix Bridge...")
        #endif

        do {
            try await MatrixBridgeService.shared.initialize()
            isMatrixInitialized = true

            #if DEBUG
            print("[App] ✅ Matrix Bridge 初始化成功")
            #endif
        } catch {
            #if DEBUG
            print("[App] ❌ Matrix Bridge 初始化失敗: \(error)")
            #endif
            // Matrix 初始化失敗不影響 App 正常使用
            // 聊天功能會回退到 REST API
        }
    }

    /// 關閉 Matrix Bridge - 在用戶登出時調用
    @MainActor
    private func shutdownMatrixBridge() async {
        guard isMatrixInitialized else { return }

        #if DEBUG
        print("[App] 正在關閉 Matrix Bridge...")
        #endif

        await MatrixBridgeService.shared.shutdown()
        isMatrixInitialized = false

        #if DEBUG
        print("[App] Matrix Bridge 已關閉")
        #endif
    }

    // MARK: - Push Notifications

    /// 設置推送通知 - 在用戶登入後觸發
    @MainActor
    private func setupPushNotifications() async {
        // 檢查當前通知設置
        await pushManager.checkNotificationSettings()

        // 如果尚未授權，請求權限
        if !pushManager.isAuthorized {
            let granted = await pushManager.requestAuthorization()

            #if DEBUG
            print("[App] Push notification authorization: \(granted ? "granted" : "denied")")
            #endif
        } else {
            // 已授權，直接註冊遠程通知
            await pushManager.registerForRemoteNotifications()
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
                    case .groupChat:
                        GroupChatView(currentPage: $currentPage, groupName: "Group Chat")
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
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // 当 App 进入后台时，标记已进入后台
                if newPhase == .background {
                    hasEnteredBackground = true
                    // Matrix: 進入後台時停止同步以節省電量
                    MatrixService.shared.stopSync()
                }
                // 当 App 从后台返回到活跃状态时，显示 Splash Screen
                if newPhase == .active && hasEnteredBackground {
                    hasEnteredBackground = false
                    currentPage = .splash

                    // Matrix: 返回前台時重新啟動同步
                    if isMatrixInitialized {
                        Task {
                            try? await MatrixService.shared.startSync()
                        }
                    }
                }
            }
            // 監聽認證狀態變化
            .onChange(of: authManager.isAuthenticated) { wasAuthenticated, isAuthenticated in
                if isAuthenticated && !wasAuthenticated {
                    // 用戶剛登入 - 初始化 Matrix
                    Task { @MainActor in
                        await initializeMatrixBridge()
                    }
                    // 用戶剛登入 - 請求推送通知權限
                    Task { @MainActor in
                        await setupPushNotifications()
                    }
                } else if !isAuthenticated && wasAuthenticated {
                    // 用戶登出或 Session 過期 - 強制跳轉到歡迎頁面
                    currentPage = .welcome
                    // 關閉 Matrix
                    Task { @MainActor in
                        await shutdownMatrixBridge()
                    }
                    // 取消註冊推送通知
                    Task { @MainActor in
                        await pushManager.unregisterToken()
                    }
                }
            }
            // Handle deep links for password reset
            .onOpenURL { url in
                handleDeepLink(url)
            }
            // Present reset password view when token is available
            .fullScreenCover(isPresented: $showResetPasswordView) {
                if let token = resetPasswordToken {
                    ResetPasswordView(resetToken: token)
                        .environmentObject(authManager)
                }
            }
        }
    }

    // MARK: - Deep Link Handler

    /// Handle incoming deep links
    /// Supports: nova://reset-password?token=xxx
    ///           https://app.icered.com/reset-password?token=xxx
    private func handleDeepLink(_ url: URL) {
        #if DEBUG
        print("[App] Received deep link: \(url)")
        #endif

        // Check for password reset path
        let pathComponents = url.pathComponents
        let host = url.host?.lowercased()

        // Handle both custom scheme (nova://) and universal link (https://)
        let isResetPassword = (host == "reset-password") ||
                              (pathComponents.contains("reset-password"))

        if isResetPassword {
            // Extract token from query parameters
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
               let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
               !token.isEmpty {
                resetPasswordToken = token
                showResetPasswordView = true

                #if DEBUG
                print("[App] Opening password reset with token: \(token.prefix(8))...")
                #endif
            } else {
                #if DEBUG
                print("[App] Password reset link missing token parameter")
                #endif
            }
        }
    }
}
