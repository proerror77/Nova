import SwiftUI

@main
struct IceredApp: App {
    // Connect AppDelegate for push notifications
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // App 持有全局认证状态，并下发 EnvironmentObject
    // Note: Using @ObservedObject for singletons to avoid lifecycle issues
    // @StateObject is designed for objects created by the view, not pre-existing singletons
    @ObservedObject private var authManager = AuthenticationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var pushManager = PushNotificationManager.shared
    @ObservedObject private var uploadManager = BackgroundUploadManager.shared
    @State private var currentPage: AppPage

    // State restoration - persist selected tab across app launches
    @SceneStorage("selectedTab") private var selectedTabRaw: String = MainTab.home.rawValue

    // App Coordinator for centralized navigation
    private let coordinator = AppCoordinator.shared

    // 监听 App 生命周期状态
    @Environment(\.scenePhase) private var scenePhase
    // 记录进入后台的时间戳
    @State private var backgroundEntryTime: Date?
    // 后台超时时间（30分钟）- 更友好的用户体验
    // 只有超过30分钟才会显示 splash screen 重新验证
    private let backgroundTimeout: TimeInterval = 1800

    // Check if running in UI testing mode
    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    init() {
        // Validate custom fonts are loaded correctly (Debug only)
        #if DEBUG
        Typography.validateFonts()
        #endif

        // Reset auth state and skip to login when running UI tests
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            // Use MainActor.assumeIsolated for safe access to @MainActor singleton
            // App init() runs on main thread but isn't automatically MainActor isolated
            MainActor.assumeIsolated {
                AuthenticationManager.shared.isAuthenticated = false
            }
            // Then run full async cleanup (clears keychain, tokens, etc.)
            Task { @MainActor in
                await AuthenticationManager.shared.logout()
            }
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
                    case .inviteCode:
                        InviteCodeView(currentPage: $currentPage)
                            .transition(.identity)
                    case .login:
                        LoginView(currentPage: $currentPage)
                            .transition(.identity)
                    case .createAccount:
                        CreateAccountView(currentPage: $currentPage)
                            .transition(.identity)
                    case .createAccountEmail:
                        CreateAccountEmailView(currentPage: $currentPage)
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
                    case .login, .createAccount, .createAccountEmail, .inviteCode:
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
                    case .friendRequests:
                        FriendRequestsView(currentPage: $currentPage)
                            .transition(.identity)
                    case .newChat:
                        NewChatView(currentPage: $currentPage)
                            .transition(.identity)
                    case .getVerified:
                        GetVerifiedView(currentPage: $currentPage)
                            .transition(.identity)
                    case .passkeys:
                        if #available(iOS 16.0, *) {
                            PasskeySettingsView(currentPage: $currentPage)
                                .transition(.identity)
                        } else {
                            // Fallback for older iOS versions
                            Text("Passkeys require iOS 16 or later")
                                .transition(.identity)
                        }
                    case .chatBackup:
                        ChatBackupView(currentPage: $currentPage)
                            .transition(.identity)
                    case .callRecordings:
                        CallRecordingsView(currentPage: $currentPage)
                            .transition(.identity)
                    default:
                        HomeView(currentPage: $currentPage)
                            .transition(.identity)
                    }
                }

                // Global upload progress overlay
                UploadProgressOverlay()
            }
            .animation(.none, value: currentPage)
            .environmentObject(authManager)
            .environmentObject(themeManager)
            .environmentObject(pushManager)
            .environmentObject(uploadManager)
            .environment(\.appCoordinator, coordinator)
            .preferredColorScheme(themeManager.colorScheme)
            .task {
                // Check notification settings on app launch
                await pushManager.checkNotificationSettings()
                await initializeMatrixBridgeIfNeeded()
            }
            .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                // Request push notification permission when user logs in
                if isAuthenticated {
                    // Sync coordinator state
                    coordinator.isAuthenticated = true

                    // Process any pending deep link first
                    if coordinator.pendingDeepLink != nil {
                        coordinator.processPendingDeepLink()
                        currentPage = coordinator.currentPage
                    } else {
                        // Navigate to home after login
                        currentPage = .home
                    }

                    // Restore selected tab from state
                    if let tab = MainTab(rawValue: selectedTabRaw) {
                        coordinator.selectTab(tab)
                    }

                    Task {
                        let pushGranted = await pushManager.requestAuthorization()
                        #if DEBUG
                        print("[App] Push notification authorization: \(pushGranted ? "granted" : "denied")")
                        #endif
                        await initializeMatrixBridgeIfNeeded()
                    }
                } else {
                    // Navigate to login page on logout
                    currentPage = .login
                    coordinator.onLogout()
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SessionExpired"))) { notification in
                // Handle session expiration - navigate to login immediately
                handleSessionExpired(notification.userInfo)
            }
            // MARK: - Action Button Intent Handling
            .onReceive(NotificationCenter.default.publisher(for: .openAliceVoiceMode)) { _ in
                // Handle Alice Voice Mode intent from Action Button (iPhone 15 Pro+)
                #if DEBUG
                print("[App] Received Alice Voice Mode intent from Action Button")
                #endif
                coordinator.navigateToAliceVoiceMode()
                // Also update currentPage if authenticated
                if coordinator.isAuthenticated {
                    currentPage = .alice
                }
            }
            // Use UIApplication.didBecomeActiveNotification as more reliable trigger for voice mode intent
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                checkForVoiceModeIntent()
            }
            // MARK: - Deep Link Handling
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // 当 App 进入后台时，记录时间戳并暂停同步
                if newPhase == .background {
                    backgroundEntryTime = Date()
                    // Save coordinator state for restoration
                    coordinator.saveState()
                    selectedTabRaw = coordinator.selectedTab.rawValue
                    print("[App] 📱 App entered background")

                    // Pause Matrix sync to save resources
                    MatrixBridgeService.shared.pauseSync()
                }
                // Check for Action Button voice mode request when becoming active
                if newPhase == .active {
                    checkForVoiceModeIntent()
                }
                // 当 App 从后台返回到活跃状态时
                if newPhase == .active, let entryTime = backgroundEntryTime {
                    let timeInBackground = Date().timeIntervalSince(entryTime)
                    print("[App] 📱 App returned to foreground after \(String(format: "%.1f", timeInBackground))s")

                    // 持久化登录策略：只有超过 30 分钟才显示 Splash Screen
                    // 短时间后台返回不做任何验证，依赖 API 层面的 401 处理
                    // 这样可以避免不必要的登出，提供更好的用户体验
                    if timeInBackground >= backgroundTimeout {
                        print("[App] ⏰ Background timeout (30min) exceeded, showing splash screen")
                        currentPage = .splash
                    }
                    // 移除了过于激进的 30 秒验证逻辑
                    // Token 过期时会在 API 请求时自动刷新 (401 -> refresh token)

                    // 重置时间戳
                    backgroundEntryTime = nil

                    // Resume Matrix sync to fetch any offline messages
                    // This is critical for users to receive messages sent while app was in background
                    if authManager.isAuthenticated && !authManager.isGuestMode {
                        Task {
                            do {
                                try await MatrixBridgeService.shared.resumeSync()
                                print("[App] ✅ Matrix sync resumed after returning from background")
                            } catch {
                                print("[App] ❌ Failed to resume Matrix sync: \(error)")
                            }
                        }
                    }
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
            if let postId = userInfo["post_id"] as? String {
                coordinator.navigate(to: .post(id: postId))
            } else {
                currentPage = .home
            }
        case "follow":
            // Navigate to the follower's profile
            if let userId = userInfo["user_id"] as? String {
                coordinator.navigate(to: .profile(userId: userId))
            } else {
                currentPage = .home
            }
        case "message":
            // Navigate to messages
            if let roomId = userInfo["room_id"] as? String {
                coordinator.navigate(to: .chat(roomId: roomId))
            } else {
                currentPage = .message
            }
        default:
            // Default to home
            currentPage = .home
        }
    }

    // MARK: - Session Expiration Handling

    /// Handle session expiration - immediately navigate to login
    private func handleSessionExpired(_ userInfo: [AnyHashable: Any]?) {
        print("[App] SESSION EXPIRED - Navigating to login page")
        currentPage = .login
        coordinator.onLogout()
    }

    // MARK: - Action Button Voice Mode Intent Handling

    /// Check for voice mode intent from Action Button (App Groups UserDefaults)
    /// - Parameter retryCount: Number of retry attempts remaining (for delayed checks)
    private func checkForVoiceModeIntent(retryCount: Int = 3) {
        guard let defaults = UserDefaults(suiteName: VoiceModeIntentKeys.appGroupSuiteName) else {
            print("[App] 🎤 Failed to access App Groups UserDefaults")
            return
        }

        let shouldOpenVoiceMode = defaults.bool(forKey: VoiceModeIntentKeys.shouldOpenVoiceMode)
        let timestamp = defaults.double(forKey: VoiceModeIntentKeys.voiceModeTimestamp)

        // If flag not set and we have retries left, schedule a delayed re-check
        // This handles timing where intent's perform() runs AFTER app activation
        guard shouldOpenVoiceMode else {
            if retryCount > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                    checkForVoiceModeIntent(retryCount: retryCount - 1)
                }
            }
            return
        }

        let timeSinceIntent = Date().timeIntervalSince1970 - timestamp
        guard timeSinceIntent < 10 else {
            // Clear stale flag
            defaults.set(false, forKey: VoiceModeIntentKeys.shouldOpenVoiceMode)
            defaults.synchronize()
            print("[App] 🎤 Stale voice mode intent ignored (age: \(String(format: "%.1f", timeSinceIntent))s)")
            return
        }

        // Clear the flag immediately to prevent re-triggering
        defaults.set(false, forKey: VoiceModeIntentKeys.shouldOpenVoiceMode)
        defaults.synchronize()

        // Use AuthenticationManager.shared directly to ensure we get the current state
        let isAuth = AuthenticationManager.shared.isAuthenticated
        print("[App] 🎤 Voice mode intent detected! isAuthenticated=\(isAuth)")

        // Sync coordinator auth state with AuthenticationManager.shared
        coordinator.isAuthenticated = isAuth

        if isAuth {
            // User is authenticated - navigate directly to Alice voice mode
            coordinator.selectedTab = .alice
            coordinator.shouldOpenVoiceMode = true
            currentPage = .alice
            print("[App] 🎤 Navigating to Alice Voice Mode")
        } else {
            // User not authenticated - store for after login
            coordinator.pendingDeepLink = .alice
            coordinator.shouldOpenVoiceMode = true
            print("[App] 🎤 User not authenticated, will navigate after login")
        }
    }

    // MARK: - Deep Link Handling

    /// Handle deep link URL (custom scheme or universal link)
    private func handleDeepLink(_ url: URL) {
        print("[App] 🔗 Received deep link: \(url.absoluteString)")

        // Parse the URL and navigate
        guard let route = DeepLinkHandler.shared.parse(url: url) else {
            print("[App] ❌ Failed to parse deep link URL")
            return
        }

        // If not authenticated, store for later
        if !authManager.isAuthenticated {
            coordinator.pendingDeepLink = route
            print("[App] 📝 Stored pending deep link for after login: \(route)")
            return
        }

        // Navigate to the parsed route
        coordinator.navigate(to: route)
        currentPage = route.toAppPage

        // Update tab if applicable
        if let tab = route.mainTab {
            selectedTabRaw = tab.rawValue
        }
    }

    @MainActor
    private func initializeMatrixBridgeIfNeeded() async {
        guard !isUITesting else { return }
        guard authManager.isAuthenticated, !authManager.isGuestMode else { return }

        do {
            // With useSSOLogin=false, this uses automatic token-based login (no dialog)
            try await MatrixBridgeService.shared.initialize(requireLogin: true)
        } catch {
            #if DEBUG
            print("[App] Matrix initialization failed: \(error)")
            #endif
        }
    }
}
