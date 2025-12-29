import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - OAuth Service

/// Handles OAuth authentication flows (Google, Apple)
/// Communicates with backend identity-service for token exchange
class OAuthService: NSObject {
    static let shared = OAuthService()

    private let apiClient = APIClient.shared

    // Apple Sign-In continuation for async/await
    private var appleSignInContinuation: CheckedContinuation<ASAuthorization, Error>?

    // MARK: - Pending OAuth Credentials (for invite code retry)

    /// Stores pending Apple credentials when invite code is required
    struct PendingAppleCredentials {
        let authorizationCode: String
        let identityToken: String
        let userIdentifier: String
        let email: String?
        let fullName: PersonNameComponents?
    }

    /// Pending Apple credentials for retry after invite code input
    private(set) var pendingAppleCredentials: PendingAppleCredentials?

    /// Clear pending credentials after successful sign-in or cancellation
    func clearPendingCredentials() {
        pendingAppleCredentials = nil
    }

    // MARK: - OAuth Provider

    enum OAuthProvider: String {
        case google
        case apple

        var displayName: String {
            switch self {
            case .google: return "Google"
            case .apple: return "Apple"
            }
        }
    }

    // MARK: - Response Types

    struct OAuthStartResponse: Codable {
        let authorizationUrl: String
        let state: String

        enum CodingKeys: String, CodingKey {
            case authorizationUrl = "authorization_url"
            case state
        }
    }

    struct OAuthCallbackResponse: Codable {
        let userId: String
        let token: String
        let refreshToken: String?
        let expiresIn: Int64
        let isNewUser: Bool
        let user: UserProfile?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case token
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case isNewUser = "is_new_user"
            case user
        }
    }

    // MARK: - OAuth Flow

    /// Start OAuth flow - get authorization URL from backend
    /// - Parameters:
    ///   - provider: OAuth provider (Google or Apple)
    ///   - inviteCode: Optional invite code for new user registration
    /// - Returns: OAuth start response with authorization URL
    func startOAuthFlow(provider: OAuthProvider, inviteCode: String? = nil) async throws -> OAuthStartResponse {
        let redirectUri = getRedirectUri(for: provider)

        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/oauth/\(provider.rawValue)/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "redirect_uri": redirectUri
        ]

        // Add invite code if provided
        if let inviteCode = inviteCode, !inviteCode.isEmpty {
            body["invite_code"] = inviteCode
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.startFlowFailed
        }

        #if DEBUG
        print("[OAuth] Start flow response status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("[OAuth] Start flow response: \(responseString)")
        }
        #endif

        if httpResponse.statusCode != 200 {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw OAuthError.serverError(errorResponse.message ?? errorResponse.error ?? "Start flow failed")
            }
            throw OAuthError.startFlowFailed
        }

        return try JSONDecoder().decode(OAuthStartResponse.self, from: data)
    }

    /// Complete OAuth flow - exchange code for tokens
    func completeOAuthFlow(
        provider: OAuthProvider,
        code: String,
        state: String
    ) async throws -> OAuthCallbackResponse {
        let redirectUri = getRedirectUri(for: provider)

        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/oauth/\(provider.rawValue)/callback")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "code": code,
            "state": state,
            "redirect_uri": redirectUri
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.callbackFailed
        }

        if httpResponse.statusCode != 200 {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw OAuthError.serverError(errorResponse.message ?? "Unknown error")
            }
            throw OAuthError.callbackFailed
        }

        return try JSONDecoder().decode(OAuthCallbackResponse.self, from: data)
    }

    // MARK: - Google Sign-In (Web-based flow with backend proxy)

    /// Pending Google state for invite code retry
    private(set) var pendingGoogleState: String?

    /// Perform Google Sign-In using ASWebAuthenticationSession
    /// Uses backend proxy flow: Google redirects to backend, backend exchanges tokens and redirects to iOS
    /// - Parameter inviteCode: Optional invite code for new user registration
    /// - Returns: OAuth callback response with tokens
    /// - Throws: `OAuthError.inviteCodeRequired` if new user without invite code
    @MainActor
    func signInWithGoogle(inviteCode: String? = nil) async throws -> OAuthCallbackResponse {
        // 1. Start flow to get authorization URL (include invite code if provided)
        let startResponse = try await startOAuthFlow(provider: .google, inviteCode: inviteCode)

        // Store state for potential retry
        pendingGoogleState = startResponse.state

        // 2. Present web authentication session
        // The callback will come from the backend with tokens (not from Google with code)
        let callbackURL = try await presentWebAuth(
            url: URL(string: startResponse.authorizationUrl)!,
            callbackScheme: "icered"
        )

        // 3. Parse callback URL - backend redirects with tokens directly
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthError.invalidCallback
        }

        // Check for error in callback
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            let message = components.queryItems?.first(where: { $0.name == "message" })?.value ?? error

            // Check for invite code required error
            if message == "INVITE_CODE_REQUIRED" || message.contains("INVITE_CODE_REQUIRED") {
                throw OAuthError.inviteCodeRequired
            }

            if message.lowercased().contains("invalid invite code") {
                throw OAuthError.invalidInviteCode(message)
            }

            // Clear pending state on other errors
            pendingGoogleState = nil
            throw OAuthError.serverError(message)
        }

        // Extract tokens from callback URL (backend proxy flow)
        guard let userId = components.queryItems?.first(where: { $0.name == "user_id" })?.value,
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            pendingGoogleState = nil
            throw OAuthError.invalidCallback
        }

        // Success - clear pending state
        pendingGoogleState = nil

        let refreshToken = components.queryItems?.first(where: { $0.name == "refresh_token" })?.value
        let expiresInString = components.queryItems?.first(where: { $0.name == "expires_in" })?.value
        let expiresIn = Int64(expiresInString ?? "3600") ?? 3600
        let isNewUserString = components.queryItems?.first(where: { $0.name == "is_new_user" })?.value
        let isNewUser = isNewUserString == "true"
        let username = components.queryItems?.first(where: { $0.name == "username" })?.value ?? ""
        let email = components.queryItems?.first(where: { $0.name == "email" })?.value

        // Build response from callback parameters
        let user = UserProfile(
            id: userId,
            username: username,
            email: email,
            displayName: nil,
            avatarUrl: nil
        )

        return OAuthCallbackResponse(
            userId: userId,
            token: token,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            isNewUser: isNewUser,
            user: user
        )
    }

    /// Retry Google Sign-In with invite code
    /// Note: Google flow requires re-authentication, cannot reuse previous session
    /// - Parameter inviteCode: Invite code for new user registration
    /// - Returns: OAuth callback response with tokens
    @MainActor
    func retryGoogleSignInWithInviteCode(_ inviteCode: String) async throws -> OAuthCallbackResponse {
        return try await signInWithGoogle(inviteCode: inviteCode)
    }

    // MARK: - Apple Sign-In (Native flow)

    /// Perform Apple Sign-In using native AuthenticationServices
    /// - Parameter inviteCode: Optional invite code for new user registration
    /// - Returns: OAuth callback response with tokens
    /// - Throws: `OAuthError.inviteCodeRequired` if new user without invite code
    @MainActor
    func signInWithApple(inviteCode: String? = nil) async throws -> OAuthCallbackResponse {
        // If we have pending credentials, use them (retry with invite code)
        if let pending = pendingAppleCredentials {
            do {
                let response = try await completeAppleSignIn(
                    authorizationCode: pending.authorizationCode,
                    identityToken: pending.identityToken,
                    userIdentifier: pending.userIdentifier,
                    email: pending.email,
                    fullName: pending.fullName,
                    inviteCode: inviteCode
                )
                clearPendingCredentials()
                return response
            } catch {
                // If it fails again with invite code required, keep credentials
                if let oauthError = error as? OAuthError, oauthError.requiresInviteCode {
                    throw error
                }
                // Other errors - clear credentials
                clearPendingCredentials()
                throw error
            }
        }

        // 1. Request Apple authorization
        let authorization = try await requestAppleAuthorization()

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw OAuthError.invalidCallback
        }

        // 2. Extract authorization code
        guard let authorizationCodeData = appleIDCredential.authorizationCode,
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
            throw OAuthError.invalidCallback
        }

        // 3. Extract identity token for verification
        guard let identityTokenData = appleIDCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw OAuthError.invalidCallback
        }

        // 4. Get user info (only available on first sign-in)
        let fullName = appleIDCredential.fullName
        let email = appleIDCredential.email

        // 5. Exchange with backend
        do {
            return try await completeAppleSignIn(
                authorizationCode: authorizationCode,
                identityToken: identityToken,
                userIdentifier: appleIDCredential.user,
                email: email,
                fullName: fullName,
                inviteCode: inviteCode
            )
        } catch let error as OAuthError {
            // If invite code required, store credentials for retry
            if error.requiresInviteCode {
                pendingAppleCredentials = PendingAppleCredentials(
                    authorizationCode: authorizationCode,
                    identityToken: identityToken,
                    userIdentifier: appleIDCredential.user,
                    email: email,
                    fullName: fullName
                )
            }
            throw error
        }
    }

    /// Retry Apple Sign-In with invite code (uses stored credentials)
    /// - Parameter inviteCode: Invite code for new user registration
    /// - Returns: OAuth callback response with tokens
    @MainActor
    func retryAppleSignInWithInviteCode(_ inviteCode: String) async throws -> OAuthCallbackResponse {
        guard pendingAppleCredentials != nil else {
            throw OAuthError.invalidCallback
        }
        return try await signInWithApple(inviteCode: inviteCode)
    }

    /// Request Apple authorization using ASAuthorizationController
    @MainActor
    private func requestAppleAuthorization() async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.appleSignInContinuation = continuation

            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.presentationContextProvider = self
            authorizationController.performRequests()
        }
    }

    /// Complete Apple Sign-In by exchanging credentials with backend
    /// - Parameters:
    ///   - authorizationCode: Authorization code from Apple
    ///   - identityToken: Identity token from Apple
    ///   - userIdentifier: Unique user identifier from Apple
    ///   - email: User's email (only available on first sign-in)
    ///   - fullName: User's full name (only available on first sign-in)
    ///   - inviteCode: Optional invite code for new user registration
    /// - Returns: OAuth callback response with tokens
    /// - Throws: `OAuthError.inviteCodeRequired` if new user without invite code
    private func completeAppleSignIn(
        authorizationCode: String,
        identityToken: String,
        userIdentifier: String,
        email: String?,
        fullName: PersonNameComponents?,
        inviteCode: String? = nil
    ) async throws -> OAuthCallbackResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/oauth/apple/native")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "authorization_code": authorizationCode,
            "identity_token": identityToken,
            "user_identifier": userIdentifier
        ]

        if let email = email {
            body["email"] = email
        }

        if let fullName = fullName {
            var nameDict: [String: String] = [:]
            if let givenName = fullName.givenName {
                nameDict["given_name"] = givenName
            }
            if let familyName = fullName.familyName {
                nameDict["family_name"] = familyName
            }
            if !nameDict.isEmpty {
                body["full_name"] = nameDict
            }
        }

        // Add invite code if provided
        if let inviteCode = inviteCode, !inviteCode.isEmpty {
            body["invite_code"] = inviteCode
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.callbackFailed
        }

        if httpResponse.statusCode != 200 {
            // Parse error response and detect INVITE_CODE_REQUIRED
            throw parseOAuthError(from: data, statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(OAuthCallbackResponse.self, from: data)
    }

    /// Parse OAuth error from backend response
    private func parseOAuthError(from data: Data, statusCode: Int) -> OAuthError {
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            let message = errorResponse.message ?? errorResponse.error ?? "Unknown error"

            // Check for specific error codes from backend
            if message == "INVITE_CODE_REQUIRED" || message.contains("INVITE_CODE_REQUIRED") {
                return .inviteCodeRequired
            }

            if message.lowercased().contains("invalid invite code") {
                return .invalidInviteCode(message)
            }

            return .serverError(message)
        }

        return .callbackFailed
    }

    // MARK: - Web Authentication

    @MainActor
    private func presentWebAuth(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: OAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: OAuthError.webAuthFailed(error.localizedDescription))
                    }
                    return
                }

                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: OAuthError.invalidCallback)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = WebAuthPresentationContext.shared
            session.prefersEphemeralWebBrowserSession = false

            if !session.start() {
                continuation.resume(throwing: OAuthError.webAuthFailed("Failed to start web authentication"))
            }
        }
    }

    // MARK: - Helpers

    /// Returns the redirect URI based on the OAuth flow type
    /// For backend proxy flow (Google), we use the staging API domain (must match Google OAuth config)
    /// For native flow (Apple), we use the custom URL scheme
    private func getRedirectUri(for provider: OAuthProvider) -> String {
        switch provider {
        case .google:
            // Backend proxy flow - Google redirects to backend, backend redirects to iOS
            // MUST use the exact URL configured in Google OAuth Console
            return "https://staging-api.icered.com/api/v2/auth/oauth/google/callback"
        case .apple:
            // Apple uses native flow, but for web-based fallback use custom scheme
            return "icered://oauth/apple/callback"
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension OAuthService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        appleSignInContinuation?.resume(returning: authorization)
        appleSignInContinuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                appleSignInContinuation?.resume(throwing: OAuthError.userCancelled)
            case .failed:
                appleSignInContinuation?.resume(throwing: OAuthError.webAuthFailed("Apple Sign-In failed"))
            case .invalidResponse:
                appleSignInContinuation?.resume(throwing: OAuthError.invalidCallback)
            case .notHandled:
                appleSignInContinuation?.resume(throwing: OAuthError.webAuthFailed("Apple Sign-In not handled"))
            case .notInteractive:
                appleSignInContinuation?.resume(throwing: OAuthError.webAuthFailed("Apple Sign-In requires interaction"))
            case .unknown:
                appleSignInContinuation?.resume(throwing: OAuthError.webAuthFailed("Unknown Apple Sign-In error"))
            case .matchedExcludedCredential:
                appleSignInContinuation?.resume(throwing: OAuthError.webAuthFailed("Credential excluded"))
            @unknown default:
                appleSignInContinuation?.resume(throwing: OAuthError.webAuthFailed(error.localizedDescription))
            }
        } else {
            appleSignInContinuation?.resume(throwing: OAuthError.webAuthFailed(error.localizedDescription))
        }
        appleSignInContinuation = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension OAuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            // iOS 26+: Create window with window scene instead of empty init
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                return UIWindow(windowScene: windowScene)
            }
            // Last resort fallback - should never reach here in a running app
            return UIWindow(frame: UIScreen.main.bounds)
        }
        return window
    }
}

// MARK: - OAuth Errors

enum OAuthError: LocalizedError {
    case startFlowFailed
    case callbackFailed
    case invalidCallback
    case stateMismatch
    case userCancelled
    case webAuthFailed(String)
    case serverError(String)
    /// New user requires invite code - frontend should prompt for invite code
    case inviteCodeRequired
    /// Invalid invite code provided
    case invalidInviteCode(String)

    var errorDescription: String? {
        switch self {
        case .startFlowFailed:
            return "Failed to start OAuth flow"
        case .callbackFailed:
            return "OAuth callback failed"
        case .invalidCallback:
            return "Invalid OAuth callback"
        case .stateMismatch:
            return "OAuth state mismatch - possible CSRF attack"
        case .userCancelled:
            return "Sign-in was cancelled"
        case .webAuthFailed(let message):
            return "Web authentication failed: \(message)"
        case .serverError(let message):
            return message
        case .inviteCodeRequired:
            return "Invite code required for new account registration"
        case .invalidInviteCode(let message):
            return "Invalid invite code: \(message)"
        }
    }

    /// Check if this error requires invite code input
    var requiresInviteCode: Bool {
        if case .inviteCodeRequired = self { return true }
        return false
    }
}

// MARK: - Error Response

private struct ErrorResponse: Codable {
    let message: String?
    let error: String?
}

// MARK: - Web Auth Presentation Context

class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Get the key window for presentation
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            // iOS 26+: Create window with window scene instead of empty init
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                return UIWindow(windowScene: windowScene)
            }
            return UIWindow(frame: UIScreen.main.bounds)
        }
        return window
    }
}
