import Foundation
import AuthenticationServices

/// Central authentication service (singleton)
/// Manages auth state, tokens, and Apple Sign In
@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?

    private let keychainManager = KeychainManager()
    private let authRepository = AuthRepository()

    private init() {
        // Check for existing session on init
        loadSession()
    }

    // MARK: - Session Management
    func loadSession() {
        if let token = keychainManager.getAccessToken() {
            isAuthenticated = true
            // TODO: Fetch current user profile
            Task {
                await fetchCurrentUser()
            }
        }
    }

    func clearSession() {
        keychainManager.clearAllTokens()
        isAuthenticated = false
        currentUser = nil
    }

    // MARK: - Email/Password Auth
    func signIn(email: String, password: String) async throws {
        let result = try await authRepository.signIn(email: email, password: password)
        keychainManager.saveAccessToken(result.accessToken)
        keychainManager.saveRefreshToken(result.refreshToken)
        isAuthenticated = true
        currentUser = result.user

        // Track sign in event
        AnalyticsTracker.shared.track(.signIn(method: "email"))
    }

    func signUp(username: String, email: String, password: String) async throws {
        let result = try await authRepository.signUp(
            username: username,
            email: email,
            password: password
        )
        keychainManager.saveAccessToken(result.accessToken)
        keychainManager.saveRefreshToken(result.refreshToken)
        isAuthenticated = true
        currentUser = result.user

        // Track sign up event
        AnalyticsTracker.shared.track(.signUp(method: "email"))
    }

    func signOut() async {
        do {
            try await authRepository.signOut()
        } catch {
            print("⚠️ Sign out error: \(error)")
        }
        clearSession()

        // Track sign out event
        AnalyticsTracker.shared.track(.signOut)
    }

    // MARK: - Apple Sign In
    func signInWithApple(authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidCredential
        }

        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidToken
        }

        let result = try await authRepository.signInWithApple(
            identityToken: tokenString,
            user: credential.user,
            email: credential.email,
            fullName: credential.fullName
        )

        keychainManager.saveAccessToken(result.accessToken)
        keychainManager.saveRefreshToken(result.refreshToken)
        isAuthenticated = true
        currentUser = result.user

        // Track Apple Sign In
        AnalyticsTracker.shared.track(.signIn(method: "apple"))
    }

    // MARK: - Token Refresh
    func refreshToken() async throws {
        guard let refreshToken = keychainManager.getRefreshToken() else {
            throw AuthError.noRefreshToken
        }

        let result = try await authRepository.refreshToken(refreshToken)
        keychainManager.saveAccessToken(result.accessToken)
        keychainManager.saveRefreshToken(result.refreshToken)
    }

    // MARK: - User Profile
    private func fetchCurrentUser() async {
        do {
            currentUser = try await authRepository.getCurrentUser()
        } catch {
            print("⚠️ Failed to fetch current user: \(error)")
            clearSession()
        }
    }

    func updateProfile(displayName: String?, bio: String?, avatarData: Data?) async throws {
        guard let userId = currentUser?.id else {
            throw AuthError.notAuthenticated
        }

        let updatedUser = try await authRepository.updateProfile(
            userId: userId,
            displayName: displayName,
            bio: bio,
            avatarData: avatarData
        )
        currentUser = updatedUser

        // Track profile update
        AnalyticsTracker.shared.track(.profileUpdate)
    }

    // MARK: - Account Deletion
    func deleteAccount() async throws {
        guard let userId = currentUser?.id else {
            throw AuthError.notAuthenticated
        }

        try await authRepository.deleteAccount(userId: userId)
        clearSession()

        // Track account deletion
        AnalyticsTracker.shared.track(.accountDelete)
    }
}

// MARK: - Auth Errors
enum AuthError: LocalizedError {
    case invalidCredential
    case invalidToken
    case noRefreshToken
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidCredential: return "Invalid credentials"
        case .invalidToken: return "Invalid authentication token"
        case .noRefreshToken: return "No refresh token available"
        case .notAuthenticated: return "User not authenticated"
        }
    }
}
