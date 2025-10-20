import SwiftUI

@main
struct NovaApp: App {
    @StateObject private var coordinator = NavigationCoordinator()
    @StateObject private var authService = AuthService.shared
    @StateObject private var analyticsTracker = AnalyticsTracker.shared

    init() {
        // Configure global appearance
        configureAppearance()

        // Track app launch
        AnalyticsTracker.shared.track(.appOpen)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                        .environmentObject(coordinator)
                        .environmentObject(authService)
                } else {
                    AuthCoordinatorView()
                        .environmentObject(authService)
                }
            }
            .environmentObject(analyticsTracker)
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    private func configureAppearance() {
        // TabBar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(Theme.Colors.surface)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // NavigationBar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(Theme.Colors.surface)
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.Colors.onSurface)
        ]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }

    private func handleDeepLink(_ url: URL) {
        if let route = DeepLinkHandler.parse(url) {
            coordinator.navigate(to: route)
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedTab: MainTab = .feed

    enum MainTab {
        case feed, search, create, notifications, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $coordinator.feedPath) {
                FeedView()
                    .navigationDestination(for: AppRoute.self) { route in
                        coordinator.view(for: route)
                    }
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(MainTab.feed)

            NavigationStack(path: $coordinator.searchPath) {
                SearchView()
                    .navigationDestination(for: AppRoute.self) { route in
                        coordinator.view(for: route)
                    }
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(MainTab.search)

            Button {
                selectedTab = .create
                coordinator.navigate(to: .create)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Theme.Colors.primary)
            }
            .tabItem {
                Label("Create", systemImage: "plus.circle.fill")
            }
            .tag(MainTab.create)

            NavigationStack(path: $coordinator.notificationsPath) {
                NotificationsView()
                    .navigationDestination(for: AppRoute.self) { route in
                        coordinator.view(for: route)
                    }
            }
            .tabItem {
                Label("Activity", systemImage: "bell.fill")
            }
            .tag(MainTab.notifications)

            NavigationStack(path: $coordinator.profilePath) {
                MyProfileView()
                    .navigationDestination(for: AppRoute.self) { route in
                        coordinator.view(for: route)
                    }
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
            .tag(MainTab.profile)
        }
        .accentColor(Theme.Colors.primary)
    }
}

// MARK: - Auth Coordinator View
struct AuthCoordinatorView: View {
    @EnvironmentObject var authService: AuthService
    @State private var currentRoute: AuthRoute = .onboarding

    enum AuthRoute {
        case onboarding, signIn, signUp, appleSignInGate
    }

    var body: some View {
        NavigationStack {
            Group {
                switch currentRoute {
                case .onboarding:
                    OnboardingView(onComplete: {
                        currentRoute = .signIn
                    })
                case .signIn:
                    SignInView(
                        onSignUpTap: { currentRoute = .signUp },
                        onAppleSignInTap: { currentRoute = .appleSignInGate }
                    )
                case .signUp:
                    SignUpView(
                        onSignInTap: { currentRoute = .signIn }
                    )
                case .appleSignInGate:
                    AppleSignInGateView(
                        onBack: { currentRoute = .signIn }
                    )
                }
            }
        }
    }
}
