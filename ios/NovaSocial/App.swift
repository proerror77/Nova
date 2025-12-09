import SwiftUI

@main
struct ICEREDApp: App {
    // App 持有全局认证状态，并下发 EnvironmentObject
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @State private var currentPage: AppPage

    // 监听 App 生命周期状态
    @Environment(\.scenePhase) private var scenePhase
    // 记录 App 是否进入过后台
    @State private var hasEnteredBackground = false

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
                    case .accounts:
                        AccountsView(currentPage: $currentPage)
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
                }
                // 当 App 从后台返回到活跃状态时，显示 Splash Screen
                if newPhase == .active && hasEnteredBackground {
                    hasEnteredBackground = false
                    currentPage = .splash
                }
            }
        }
    }
}
