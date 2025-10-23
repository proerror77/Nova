//
//  DeepLinkHandler.swift
//  NovaSocial
//
//  Created by Nova Team
//  Handles deep link navigation and state management
//

import SwiftUI
import Combine

// MARK: - Deep Link Navigation State

/// Manages navigation state for deep links
@MainActor
class DeepLinkNavigationState: ObservableObject {

    // MARK: - Published Properties

    @Published var selectedTab: TabSelection = .feed
    @Published var presentedSheet: SheetType?
    @Published var navigationPath = NavigationPath()
    @Published var showAuthFlow = false

    // MARK: - Tab Selection

    enum TabSelection: String {
        case feed
        case explore
        case camera
        case notifications
        case profile
    }

    // MARK: - Sheet Types

    enum SheetType: Identifiable {
        case userProfile(userId: String)
        case post(postId: String)
        case search(query: String?)
        case settings
        case editProfile
        case emailVerification(token: String)
        case passwordReset(token: String)

        var id: String {
            switch self {
            case .userProfile(let userId):
                return "userProfile-\(userId)"
            case .post(let postId):
                return "post-\(postId)"
            case .search(let query):
                return "search-\(query ?? "")"
            case .settings:
                return "settings"
            case .editProfile:
                return "editProfile"
            case .emailVerification(let token):
                return "emailVerification-\(token)"
            case .passwordReset(let token):
                return "passwordReset-\(token)"
            }
        }
    }

    // MARK: - Reset

    func reset() {
        selectedTab = .feed
        presentedSheet = nil
        navigationPath = NavigationPath()
        showAuthFlow = false
    }
}

// MARK: - Deep Link Handler

/// Handles deep link routing and navigation
@MainActor
class DeepLinkHandler: ObservableObject {

    // MARK: - Dependencies

    private let router: DeepLinkRouter
    private let navigationState: DeepLinkNavigationState
    private let authService: AuthServiceProtocol?

    // MARK: - Published Properties

    @Published var isProcessing = false
    @Published var error: DeepLinkError?

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        router: DeepLinkRouter,
        navigationState: DeepLinkNavigationState,
        authService: AuthServiceProtocol? = nil
    ) {
        self.router = router
        self.navigationState = navigationState
        self.authService = authService

        setupObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        // Observe route changes from router
        router.$currentRoute
            .compactMap { $0 }
            .sink { [weak self] route in
                self?.navigate(to: route)
            }
            .store(in: &cancellables)
    }

    // MARK: - Handle Deep Link

    /// Handle a deep link URL
    func handle(url: URL) async {
        isProcessing = true
        error = nil

        // Parse and handle the route
        router.handle(url: url)

        isProcessing = false
    }

    // MARK: - Navigation

    private func navigate(to route: DeepLinkRoute) {
        switch route {
        // User routes
        case .userProfile(let userId):
            navigateToUserProfile(userId: userId)

        case .currentUserProfile:
            navigateToCurrentUserProfile()

        case .editProfile:
            navigationState.presentedSheet = .editProfile

        // Content routes
        case .post(let postId):
            navigateToPost(postId: postId)

        case .feed:
            navigateToFeed()

        case .explore:
            navigateToExplore()

        case .notifications:
            navigateToNotifications()

        // Search routes
        case .search(let query):
            navigateToSearch(query: query)

        case .searchHashtag(let tag):
            navigateToSearch(query: "#\(tag)")

        case .searchUsers, .searchPosts:
            navigateToSearch(query: nil)

        // Auth routes
        case .login:
            navigateToLogin()

        case .signup:
            navigateToSignup()

        case .emailVerification(let token):
            navigationState.presentedSheet = .emailVerification(token: token)

        case .passwordReset(let token):
            navigationState.presentedSheet = .passwordReset(token: token)

        case .oauth(let provider, let code):
            handleOAuth(provider: provider, code: code)

        // Settings routes
        case .settings:
            navigateToSettings()

        case .privacySettings:
            navigateToSettings(section: .privacy)

        case .accountSettings:
            navigateToSettings(section: .account)

        case .notificationSettings:
            navigateToSettings(section: .notifications)

        // Social routes
        case .followers(let userId):
            navigateToFollowers(userId: userId)

        case .following(let userId):
            navigateToFollowing(userId: userId)

        case .conversation(let conversationId):
            navigateToConversation(conversationId: conversationId)

        // Media routes
        case .camera:
            navigateToCamera()

        case .mediaLibrary:
            navigateToMediaLibrary()

        // Error handling
        case .invalid(let errorMessage):
            handleInvalidLink(error: errorMessage)

        case .unknown(let url):
            handleUnknownLink(url: url)
        }
    }

    // MARK: - Navigation Helpers

    private func navigateToUserProfile(userId: String) {
        // Check if authenticated
        guard isAuthenticated else {
            showAuthenticationRequired()
            return
        }

        navigationState.presentedSheet = .userProfile(userId: userId)
    }

    private func navigateToCurrentUserProfile() {
        navigationState.selectedTab = .profile
        navigationState.presentedSheet = nil
    }

    private func navigateToPost(postId: String) {
        navigationState.presentedSheet = .post(postId: postId)
    }

    private func navigateToFeed() {
        navigationState.selectedTab = .feed
        navigationState.presentedSheet = nil
    }

    private func navigateToExplore() {
        navigationState.selectedTab = .explore
        navigationState.presentedSheet = nil
    }

    private func navigateToNotifications() {
        guard isAuthenticated else {
            showAuthenticationRequired()
            return
        }

        navigationState.selectedTab = .notifications
        navigationState.presentedSheet = nil
    }

    private func navigateToSearch(query: String?) {
        navigationState.selectedTab = .explore
        navigationState.presentedSheet = .search(query: query)
    }

    private func navigateToLogin() {
        navigationState.showAuthFlow = true
    }

    private func navigateToSignup() {
        navigationState.showAuthFlow = true
    }

    private func navigateToSettings(section: SettingsSection? = nil) {
        guard isAuthenticated else {
            showAuthenticationRequired()
            return
        }

        navigationState.presentedSheet = .settings
        // TODO: Navigate to specific section if provided
    }

    private func navigateToFollowers(userId: String) {
        guard isAuthenticated else {
            showAuthenticationRequired()
            return
        }

        // TODO: Implement followers navigation
    }

    private func navigateToFollowing(userId: String) {
        guard isAuthenticated else {
            showAuthenticationRequired()
            return
        }

        // TODO: Implement following navigation
    }

    private func navigateToConversation(conversationId: String) {
        guard isAuthenticated else {
            showAuthenticationRequired()
            return
        }

        // TODO: Implement conversation navigation
    }

    private func navigateToCamera() {
        guard isAuthenticated else {
            showAuthenticationRequired()
            return
        }

        navigationState.selectedTab = .camera
    }

    private func navigateToMediaLibrary() {
        guard isAuthenticated else {
            showAuthenticationRequired()
            return
        }

        // TODO: Implement media library navigation
    }

    // MARK: - OAuth Handling

    private func handleOAuth(provider: String, code: String?, state: String?) {
        guard let code = code else {
            error = .invalidOAuthCallback(provider: provider)
            return
        }

        // Verify state (CSRF protection)
        if let expected = OAuthStateManager.shared.currentState() {
            guard let incoming = state, incoming == expected else {
                self.error = .invalidOAuthCallback(provider: provider)
                return
            }
        }

        Task {
            do {
                // Exchange code → tokens
                try await authorizeOAuth(provider: provider, code: code, state: state ?? "ios")
                navigateToFeed()
            } catch {
                self.error = .oauthFailed(provider: provider, error: error)
            }
        }
    }

    // Calls backend /api/v1/auth/oauth/authorize and stores tokens via AuthManager
    private func authorizeOAuth(provider: String, code: String, state: String) async throws {
        struct OAuthAuthorizeRequest: Encodable {
            let provider: String
            let code: String
            let state: String
            let redirectUri: String
        }

        struct OAuthAuthorizeResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let tokenType: String
            let expiresIn: Int
            let userId: String
            let email: String

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case tokenType = "token_type"
                case expiresIn = "expires_in"
                case userId = "user_id"
                case email
            }
        }

        let apiClient = APIClient(baseURL: AppConfig.baseURL)
        let req = OAuthAuthorizeRequest(
            provider: provider,
            code: code,
            state: state,
            redirectUri: "novasocial://auth/oauth/\(provider)"
        )

        let endpoint = APIEndpoint(
            path: "/auth/oauth/authorize",
            method: .post,
            body: req
        )

        let resp: OAuthAuthorizeResponse = try await apiClient.request(endpoint, authenticated: false)

        // Minimal user placeholder
        let userId = UUID(uuidString: resp.userId) ?? UUID()
        let username = resp.email.split(separator: "@").first.map(String.init) ?? "user"
        let user = User(
            id: userId,
            username: username,
            email: resp.email,
            displayName: nil,
            bio: nil,
            avatarUrl: nil,
            isVerified: false,
            createdAt: Date()
        )

        let tokens = AuthTokens(
            accessToken: resp.accessToken,
            refreshToken: resp.refreshToken,
            expiresIn: resp.expiresIn,
            tokenType: resp.tokenType
        )

        AuthManager.shared.saveAuth(user: user, tokens: tokens)
        OAuthStateManager.shared.clearState()
        OAuthStateManager.shared.clearNonce()
    }

    // MARK: - Error Handling

    private func handleInvalidLink(error: String) {
        self.error = .invalidRoute(message: error)
        showErrorAlert(message: error)
    }

    private func handleUnknownLink(url: URL) {
        self.error = .unknownURL(url: url)
        showErrorAlert(message: "Unable to open link: \(url.absoluteString)")
    }

    private func showAuthenticationRequired() {
        navigationState.showAuthFlow = true
        AccessibilityHelper.announce("Sign in required")
    }

    private func showErrorAlert(message: String) {
        // TODO: Show error alert
        AccessibilityHelper.announce("Error: \(message)")
    }

    // MARK: - Authentication Check

    private var isAuthenticated: Bool {
        // TODO: Check actual authentication status
        authService?.isAuthenticated ?? false
    }
}

// MARK: - Settings Section

enum SettingsSection {
    case account
    case privacy
    case notifications
    case appearance
}

// MARK: - Deep Link Error

enum DeepLinkError: LocalizedError {
    case invalidRoute(message: String)
    case unknownURL(url: URL)
    case authenticationRequired
    case invalidOAuthCallback(provider: String)
    case oauthFailed(provider: String, error: Error)

    var errorDescription: String? {
        switch self {
        case .invalidRoute(let message):
            return "Invalid deep link: \(message)"
        case .unknownURL(let url):
            return "Unknown URL: \(url.absoluteString)"
        case .authenticationRequired:
            return "You must sign in to access this content"
        case .invalidOAuthCallback(let provider):
            return "Invalid OAuth callback from \(provider)"
        case .oauthFailed(let provider, let error):
            return "OAuth failed for \(provider): \(error.localizedDescription)"
        }
    }
}

// MARK: - Auth Service Protocol

protocol AuthServiceProtocol {
    var isAuthenticated: Bool { get }
    func handleOAuthCallback(provider: String, code: String) async throws
}

// MARK: - SwiftUI Integration

extension View {

    /// Handle deep links in a SwiftUI view
    func handleDeepLinks(
        router: DeepLinkRouter,
        navigationState: DeepLinkNavigationState
    ) -> some View {
        self.onOpenURL { url in
            router.handle(url: url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
            guard let url = userActivity.webpageURL else { return }
            router.handle(url: url)
        }
    }
}

// MARK: - Deep Link Preview Provider

#if DEBUG
struct DeepLinkPreviewProvider {

    static let sampleRoutes: [DeepLinkRoute] = [
        .feed,
        .userProfile(userId: "123"),
        .post(postId: "456"),
        .search(query: "SwiftUI"),
        .searchHashtag(tag: "iOS"),
        .notifications,
        .settings
    ]

    static func previewURL(for route: DeepLinkRoute) -> URL? {
        let router = DeepLinkRouter()
        return router.generateURL(for: route)
    }

    static func testURLs() -> [URL] {
        let router = DeepLinkRouter()
        return sampleRoutes.compactMap { router.generateURL(for: $0) }
    }
}
#endif
