import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - OAuth Service

/// Handles OAuth authentication flows (Google, Apple)
/// Communicates with backend identity-service for token exchange
class OAuthService {
    static let shared = OAuthService()

    private let apiClient = APIClient.shared

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
    func startOAuthFlow(provider: OAuthProvider) async throws -> OAuthStartResponse {
        let redirectUri = getRedirectUri(for: provider)

        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/oauth/\(provider.rawValue)/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "redirect_uri": redirectUri
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
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

    // MARK: - Apple Sign-In (Native flow)

    /// Perform Apple Sign-In using native ASAuthorizationController
    func signInWithApple() async throws -> OAuthCallbackResponse {
        try await withCheckedThrowingContinuation { continuation in
            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AppleSignInDelegate(continuation: continuation)

            // Store delegate to keep it alive
            objc_setAssociatedObject(authorizationController, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

            authorizationController.delegate = delegate
            authorizationController.presentationContextProvider = WebAuthPresentationContext.shared
            authorizationController.performRequests()
        }
    }

    // MARK: - Google Sign-In (Web-based flow)

    /// Perform Google Sign-In using ASWebAuthenticationSession
    func signInWithGoogle() async throws -> OAuthCallbackResponse {
        // 1. Start flow to get authorization URL
        let startResponse = try await startOAuthFlow(provider: .google)

        // 2. Present web authentication session
        let callbackURL = try await presentWebAuth(
            url: URL(string: startResponse.authorizationUrl)!,
            callbackScheme: "icered"
        )

        // 3. Extract code and state from callback URL
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            throw OAuthError.invalidCallback
        }

        // Verify state matches
        guard returnedState == startResponse.state else {
            throw OAuthError.stateMismatch
        }

        // 4. Exchange code for tokens
        return try await completeOAuthFlow(
            provider: .google,
            code: code,
            state: startResponse.state
        )
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

    private func getRedirectUri(for provider: OAuthProvider) -> String {
        // Use custom URL scheme for iOS callback
        return "icered://oauth/\(provider.rawValue)/callback"
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
        }
    }
}

// MARK: - Error Response

private struct ErrorResponse: Codable {
    let message: String?
    let error: String?
}

// MARK: - Web Auth Presentation Context

class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding, ASAuthorizationControllerPresentationContextProviding {
    static let shared = WebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Get the key window for presentation
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Apple Sign-In Delegate

private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let continuation: CheckedContinuation<OAuthService.OAuthCallbackResponse, Error>

    init(continuation: CheckedContinuation<OAuthService.OAuthCallbackResponse, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation.resume(throwing: OAuthError.invalidCallback)
            return
        }

        let userId = appleIDCredential.user

        // Get identity token
        guard let identityTokenData = appleIDCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            continuation.resume(throwing: OAuthError.invalidCallback)
            return
        }

        // Build display name from full name components
        var displayName: String?
        if let fullName = appleIDCredential.fullName {
            let components = [fullName.givenName, fullName.familyName].compactMap { $0 }
            if !components.isEmpty {
                displayName = components.joined(separator: " ")
            }
        }

        // Create user profile
        let user = UserProfile(
            id: userId,
            username: "user_\(userId.prefix(8))",
            email: appleIDCredential.email,
            displayName: displayName,
            bio: nil,
            avatarUrl: nil,
            coverUrl: nil,
            website: nil,
            location: nil,
            isVerified: false,
            isPrivate: false,
            isBanned: false,
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil,
            firstName: appleIDCredential.fullName?.givenName,
            lastName: appleIDCredential.fullName?.familyName,
            dateOfBirth: nil,
            gender: nil
        )

        // Return response with Apple identity token
        let response = OAuthService.OAuthCallbackResponse(
            userId: userId,
            token: identityToken,
            refreshToken: nil,
            expiresIn: 3600,
            isNewUser: appleIDCredential.email != nil, // If email is provided, likely new user
            user: user
        )

        continuation.resume(returning: response)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                continuation.resume(throwing: OAuthError.userCancelled)
            case .failed:
                continuation.resume(throwing: OAuthError.webAuthFailed("Apple Sign-In failed"))
            case .invalidResponse:
                continuation.resume(throwing: OAuthError.invalidCallback)
            case .notHandled:
                continuation.resume(throwing: OAuthError.webAuthFailed("Apple Sign-In not handled"))
            case .unknown:
                continuation.resume(throwing: OAuthError.webAuthFailed("Unknown error"))
            case .notInteractive:
                continuation.resume(throwing: OAuthError.webAuthFailed("Not interactive"))
            case .matchedExcludedCredential:
                continuation.resume(throwing: OAuthError.webAuthFailed("Excluded credential"))
            @unknown default:
                continuation.resume(throwing: OAuthError.webAuthFailed(error.localizedDescription))
            }
        } else {
            continuation.resume(throwing: OAuthError.webAuthFailed(error.localizedDescription))
        }
    }
}
