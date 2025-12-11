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

    // MARK: - Apple Sign-In (Native flow)

    /// Perform Apple Sign-In using native AuthenticationServices
    @MainActor
    func signInWithApple() async throws -> OAuthCallbackResponse {
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
        return try await completeAppleSignIn(
            authorizationCode: authorizationCode,
            identityToken: identityToken,
            userIdentifier: appleIDCredential.user,
            email: email,
            fullName: fullName
        )
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
    private func completeAppleSignIn(
        authorizationCode: String,
        identityToken: String,
        userIdentifier: String,
        email: String?,
        fullName: PersonNameComponents?
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

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.callbackFailed
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw OAuthError.serverError(errorResponse.message ?? "Unknown error")
            }
            throw OAuthError.callbackFailed
        }

        return try JSONDecoder().decode(OAuthCallbackResponse.self, from: data)
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
            return UIWindow()
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

class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Get the key window for presentation
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }
}
