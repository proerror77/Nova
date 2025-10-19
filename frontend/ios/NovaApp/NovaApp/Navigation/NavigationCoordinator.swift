import SwiftUI

/// Central navigation coordinator for the entire app
/// Manages 5 independent navigation stacks (one per tab)
@MainActor
class NavigationCoordinator: ObservableObject {
    // MARK: - Navigation Paths (5 tabs)
    @Published var feedPath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var createPath = NavigationPath()
    @Published var notificationsPath = NavigationPath()
    @Published var profilePath = NavigationPath()

    // MARK: - Active Sheet
    @Published var activeSheet: AppRoute?
    @Published var activeFullScreenCover: AppRoute?

    // MARK: - Navigation Actions
    func navigate(to route: AppRoute) {
        // Track navigation event
        AnalyticsTracker.shared.track(.navigation(to: route.analyticsName))

        // Route to appropriate navigation stack
        switch route {
        case .feed, .postDetail, .comments:
            feedPath.append(route)

        case .search, .userResults:
            searchPath.append(route)

        case .create, .photoPicker, .imageEdit, .publishForm, .uploadQueue:
            createPath.append(route)

        case .notifications:
            notificationsPath.append(route)

        case .profile, .editProfile:
            profilePath.append(route)

        case .settings, .deleteAccount, .policy:
            profilePath.append(route)

        default:
            // Unknown route - log error
            print("⚠️ Unknown route: \(route)")
        }
    }

    func navigateToRoot(tab: MainTabType) {
        switch tab {
        case .feed:
            feedPath.removeLast(feedPath.count)
        case .search:
            searchPath.removeLast(searchPath.count)
        case .create:
            createPath.removeLast(createPath.count)
        case .notifications:
            notificationsPath.removeLast(notificationsPath.count)
        case .profile:
            profilePath.removeLast(profilePath.count)
        }
    }

    func pop() {
        // Pop from currently active stack
        if !feedPath.isEmpty {
            feedPath.removeLast()
        } else if !searchPath.isEmpty {
            searchPath.removeLast()
        } else if !createPath.isEmpty {
            createPath.removeLast()
        } else if !notificationsPath.isEmpty {
            notificationsPath.removeLast()
        } else if !profilePath.isEmpty {
            profilePath.removeLast()
        }
    }

    func presentSheet(_ route: AppRoute) {
        activeSheet = route
    }

    func presentFullScreenCover(_ route: AppRoute) {
        activeFullScreenCover = route
    }

    func dismissSheet() {
        activeSheet = nil
    }

    func dismissFullScreenCover() {
        activeFullScreenCover = nil
    }

    // MARK: - View Builder
    @ViewBuilder
    func view(for route: AppRoute) -> some View {
        switch route {
        // Auth
        case .onboarding:
            OnboardingView(onComplete: {})
        case .signIn:
            SignInView(onSignUpTap: {}, onAppleSignInTap: {})
        case .signUp:
            SignUpView(onSignInTap: {})
        case .appleSignInGate:
            AppleSignInGateView(onBack: {})

        // Feed
        case .feed:
            FeedView()
        case .postDetail(let postId):
            PostDetailView(postId: postId)
        case .comments(let postId):
            CommentsSheet(postId: postId)

        // Create
        case .create:
            CreateEntryView()
        case .photoPicker:
            PhotoPickerView()
        case .imageEdit(let imageData):
            ImageEditView(imageData: imageData)
        case .publishForm(let imageData):
            PublishFormView(imageData: imageData)
        case .uploadQueue:
            UploadQueueView()

        // Search
        case .search:
            SearchView()
        case .userResults(let query):
            UserResultListView(query: query)

        // Profile
        case .profile(let userId):
            if let userId = userId {
                UserProfileView(userId: userId)
            } else {
                MyProfileView()
            }
        case .editProfile:
            EditProfileView()

        // Notifications
        case .notifications:
            NotificationsView()

        // Settings
        case .settings:
            SettingsView()
        case .deleteAccount:
            DeleteAccountFlow()
        case .policy(let url):
            PolicyWebView(url: url)

        // Deep Link
        case .deepLink(let url):
            Text("Deep Link: \(url.absoluteString)")
                .font(Theme.Typography.body)
        }
    }
}

// MARK: - Supporting Types
enum MainTabType {
    case feed, search, create, notifications, profile
}

// MARK: - Analytics Event Extension
extension AnalyticsEvent {
    static func navigation(to screen: String) -> AnalyticsEvent {
        .custom(name: "screen_view", parameters: ["screen_name": screen])
    }
}
