import Foundation
import SafariServices

// MARK: - OAuth Extension for AuthViewModel
extension AuthViewModel {
    /// Initiates OAuth flow with the specified provider
    /// - Parameter provider: OAuth provider (google, apple, facebook)
    func initiateOAuthFlow(provider: String) {
        isLoading = true

        // Generate PKCE parameters
        let (codeVerifier, codeChallenge, method) = OAuthStateManager.shared.generatePKCE()

        // Generate state for CSRF protection
        let state = OAuthStateManager.shared.generateState()

        // Generate nonce for OpenID Connect providers
        let nonce = OAuthStateManager.shared.generateNonce()

        // Build authorization URL based on provider
        guard let authURL = buildOAuthURL(
            provider: provider,
            state: state,
            codeChallenge: codeChallenge,
            codeChallengeMethod: method,
            nonce: nonce
        ) else {
            showErrorMessage("Failed to build OAuth URL")
            isLoading = false
            return
        }

        // Launch Safari to handle OAuth flow
        DispatchQueue.main.async {
            self.launchSafariOAuth(url: authURL)
            self.isLoading = false
        }
    }

    /// Handles OAuth callback after user completes authentication
    /// - Parameters:
    ///   - url: Callback URL from OAuth provider
    ///   - provider: OAuth provider that initiated the flow
    func handleOAuthCallback(url: URL, provider: String) async {
        isLoading = true
        errorMessage = nil

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            showErrorMessage("Invalid callback URL")
            isLoading = false
            return
        }

        // Extract authorization code from callback
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
                showErrorMessage("OAuth error: \(error)")
            } else {
                showErrorMessage("No authorization code in callback")
            }
            isLoading = false
            return
        }

        // Extract state parameter (CSRF protection)
        guard let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            showErrorMessage("Missing state in callback")
            isLoading = false
            return
        }

        // Validate state token (CSRF protection)
        guard state == OAuthStateManager.shared.currentState() else {
            showErrorMessage("State mismatch: potential CSRF attack detected")
            OAuthStateManager.shared.clearState()
            OAuthStateManager.shared.clearPKCE()
            OAuthStateManager.shared.clearNonce()
            isLoading = false
            return
        }

        // Retrieve stored code verifier for PKCE
        guard let codeVerifier = OAuthStateManager.shared.currentCodeVerifier() else {
            showErrorMessage("Code verifier not found")
            isLoading = false
            return
        }

        do {
            // Exchange authorization code for access token
            let tokens = try await exchangeCodeForTokens(
                code: code,
                codeVerifier: codeVerifier,
                provider: provider
            )

            // Validate nonce (for OpenID Connect providers)
            if ["google", "apple"].contains(provider) {
                guard try validateNonce(in: tokens.idToken) else {
                    showErrorMessage("Nonce validation failed")
                    isLoading = false
                    return
                }
            }

            // Save tokens securely
            try saveOAuthTokens(tokens: tokens, provider: provider)

            // Clear OAuth state (single-use tokens)
            OAuthStateManager.shared.clearState()
            OAuthStateManager.shared.clearPKCE()
            OAuthStateManager.shared.clearNonce()

            // Update app state
            appState.isAuthenticated = true

            isLoading = false
        } catch {
            showErrorMessage("OAuth authentication failed: \(error.localizedDescription)")
            isLoading = false
        }
    }

    // MARK: - Private OAuth Helpers

    /// Builds the OAuth authorization URL for the specified provider
    private func buildOAuthURL(
        provider: String,
        state: String,
        codeChallenge: String,
        codeChallengeMethod: String,
        nonce: String
    ) -> URL? {
        var components = URLComponents()

        switch provider.lowercased() {
        case "google":
            components.scheme = "https"
            components.host = "accounts.google.com"
            components.path = "/o/oauth2/v2/auth"

            components.queryItems = [
                URLQueryItem(name: "client_id", value: AppConfig.googleClientId),
                URLQueryItem(name: "redirect_uri", value: AppConfig.googleRedirectUri),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: "openid profile email"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod),
                URLQueryItem(name: "nonce", value: nonce),
                URLQueryItem(name: "prompt", value: "consent"),
            ]

        case "apple":
            components.scheme = "https"
            components.host = "appleid.apple.com"
            components.path = "/auth/authorize"

            components.queryItems = [
                URLQueryItem(name: "client_id", value: AppConfig.appleClientId),
                URLQueryItem(name: "redirect_uri", value: AppConfig.appleRedirectUri),
                URLQueryItem(name: "response_type", value: "code id_token"),
                URLQueryItem(name: "response_mode", value: "form_post"),
                URLQueryItem(name: "scope", value: "openid email name"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "nonce", value: nonce),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod),
            ]

        case "facebook":
            components.scheme = "https"
            components.host = "www.facebook.com"
            components.path = "/v13.0/dialog/oauth"

            components.queryItems = [
                URLQueryItem(name: "client_id", value: AppConfig.facebookClientId),
                URLQueryItem(name: "redirect_uri", value: AppConfig.facebookRedirectUri),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: "public_profile email"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod),
            ]

        default:
            return nil
        }

        return components.url
    }

    /// Launches Safari to handle OAuth flow
    private func launchSafariOAuth(url: URL) {
        // This would be called from the view to present Safari
        // Note: Actual presentation logic should be in the View, not the ViewModel
        NotificationCenter.default.post(
            name: NSNotification.Name("LaunchSafariOAuth"),
            object: url
        )
    }

    /// Exchanges authorization code for access tokens
    private func exchangeCodeForTokens(
        code: String,
        codeVerifier: String,
        provider: String
    ) async throws -> OAuthTokenResponse {
        let tokenEndpoint = getTokenEndpoint(provider: provider)

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Build request body based on provider
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "client_id", value: getClientId(provider: provider)),
            URLQueryItem(name: "client_secret", value: getClientSecret(provider: provider)),
            URLQueryItem(name: "redirect_uri", value: getRedirectUri(provider: provider)),
        ]

        if let body = bodyComponents.percentEncodedQuery?.data(using: .utf8) {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OAuth", code: -1, userInfo: nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "OAuth",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Token exchange failed"]
            )
        }

        let decoder = JSONDecoder()
        let tokenResponse = try decoder.decode(OAuthTokenResponse.self, from: data)

        return tokenResponse
    }

    /// Validates nonce in ID token (OpenID Connect)
    private func validateNonce(in idToken: String) throws -> Bool {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return false }

        // Decode JWT payload (second part)
        let payloadData = try base64URLDecode(String(parts[1]))
        let decoder = JSONDecoder()

        if let payload = try? decoder.decode([String: String].self, from: payloadData),
           let nonce = payload["nonce"],
           nonce == OAuthStateManager.shared.currentNonce() {
            return true
        }

        return false
    }

    /// Saves OAuth tokens securely to Keychain
    private func saveOAuthTokens(tokens: OAuthTokenResponse, provider: String) throws {
        // Use Keychain for secure storage
        let keyPrefix = "oauth_\(provider)"

        // In production, use SecKeychainAddGenericPassword or similar
        // For now, using UserDefaults (NOT RECOMMENDED for production)
        UserDefaults.standard.set(tokens.accessToken, forKey: "\(keyPrefix)_access_token")
        if let refreshToken = tokens.refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: "\(keyPrefix)_refresh_token")
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "\(keyPrefix)_created_at")
    }

    // MARK: - Provider-Specific Helpers

    private func getTokenEndpoint(provider: String) -> URL {
        switch provider.lowercased() {
        case "google":
            return URL(string: "https://oauth2.googleapis.com/token")!
        case "apple":
            return URL(string: "https://appleid.apple.com/auth/token")!
        case "facebook":
            return URL(string: "https://graph.instagram.com/oauth/access_token")!
        default:
            return URL(string: "https://localhost")!
        }
    }

    private func getClientId(provider: String) -> String {
        switch provider.lowercased() {
        case "google":
            return AppConfig.googleClientId
        case "apple":
            return AppConfig.appleClientId
        case "facebook":
            return AppConfig.facebookClientId
        default:
            return ""
        }
    }

    private func getClientSecret(provider: String) -> String {
        switch provider.lowercased() {
        case "google":
            return AppConfig.googleClientSecret
        case "apple":
            return AppConfig.appleClientSecret
        case "facebook":
            return AppConfig.facebookClientSecret
        default:
            return ""
        }
    }

    private func getRedirectUri(provider: String) -> String {
        switch provider.lowercased() {
        case "google":
            return AppConfig.googleRedirectUri
        case "apple":
            return AppConfig.appleRedirectUri
        case "facebook":
            return AppConfig.facebookRedirectUri
        default:
            return ""
        }
    }

    // MARK: - Utilities

    /// Decodes BASE64URL-encoded string
    private func base64URLDecode(_ string: String) throws -> Data {
        var base64 = string
        base64 = base64.replacingOccurrences(of: "-", with: "+")
        base64 = base64.replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64) else {
            throw NSError(domain: "Base64URLDecode", code: -1)
        }

        return data
    }
}

// MARK: - OAuth Models

struct OAuthTokenResponse: Codable {
    let accessToken: String
    let tokenType: String?
    let refreshToken: String?
    let expiresIn: Int?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
    }
}
