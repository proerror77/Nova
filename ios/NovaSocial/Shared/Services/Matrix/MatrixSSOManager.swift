import Foundation
import AuthenticationServices
import Combine
import UIKit

// MARK: - Matrix SSO Manager
//
// Implements standard Matrix SSO login flow using Zitadel (Nova's identity provider)
//
// Flow:
// 1. Check Synapse supports SSO via GET /_matrix/client/v3/login
// 2. Open WebView/Safari to /_matrix/client/v3/login/sso/redirect?redirectUrl=...
// 3. User authenticates via Zitadel (Nova account)
// 4. Redirect back to app with loginToken parameter
// 5. Exchange loginToken for Matrix access_token via m.login.token
//
// Note: This replaces the legacy /api/v2/matrix/token endpoint which returned
// a service account token instead of a user-specific token.

@MainActor
@Observable
final class MatrixSSOManager {

    // MARK: - Singleton

    static let shared = MatrixSSOManager()

    // MARK: - Configuration

    /// Matrix homeserver URL based on environment
    var homeserverURL: String {
        MatrixSSOConfiguration.homeserverURL
    }

    /// SSO callback URL scheme based on environment
    var ssoCallbackURL: String {
        MatrixSSOConfiguration.ssoCallbackURL
    }

    // MARK: - State

    private(set) var isLoggingIn = false
    private(set) var ssoAvailable = false
    private(set) var lastError: MatrixSSOError?

    /// Login completion continuation for async/await pattern
    private var loginContinuation: CheckedContinuation<MatrixSSOLoginResult, Error>?

    /// ASWebAuthenticationSession for secure SSO flow
    private var authSession: ASWebAuthenticationSession?

    // MARK: - Dependencies

    private let keychain = KeychainService.shared
    private let urlSession: URLSession

    // MARK: - Initialization

    private init() {
        // Create URLSession with custom configuration for Matrix API calls
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)

        #if DEBUG
        print("[MatrixSSO] Initialized with homeserver: \(homeserverURL)")
        #endif
    }

    // MARK: - SSO Availability Check

    /// Check if the Matrix homeserver supports SSO login
    /// Calls GET /_matrix/client/v3/login and looks for m.login.sso flow
    func checkSSOAvailable() async throws -> Bool {
        #if DEBUG
        print("[MatrixSSO] Checking SSO availability at \(homeserverURL)")
        #endif

        let loginEndpoint = "\(homeserverURL)/_matrix/client/v3/login"

        guard let url = URL(string: loginEndpoint) else {
            throw MatrixSSOError.invalidURL(loginEndpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MatrixSSOError.networkError("Invalid response type")
            }

            guard httpResponse.statusCode == 200 else {
                throw MatrixSSOError.serverError(httpResponse.statusCode, "Failed to get login flows")
            }

            // Parse login flows response
            let loginFlows = try JSONDecoder().decode(MatrixLoginFlowsResponse.self, from: data)

            // Check for m.login.sso or m.login.token flow
            let hasSSOFlow = loginFlows.flows.contains { flow in
                flow.type == "m.login.sso" || flow.type == "m.login.token"
            }

            self.ssoAvailable = hasSSOFlow

            #if DEBUG
            print("[MatrixSSO] SSO available: \(hasSSOFlow)")
            print("[MatrixSSO] Available flows: \(loginFlows.flows.map { $0.type })")
            #endif

            return hasSSOFlow
        } catch let error as MatrixSSOError {
            throw error
        } catch {
            throw MatrixSSOError.networkError(error.localizedDescription)
        }
    }

    // MARK: - SSO Login Flow

    /// Start the SSO login flow
    /// Opens ASWebAuthenticationSession to Matrix SSO redirect URL
    /// Returns when user completes authentication or cancels
    func startSSOLogin() async throws -> MatrixSSOLoginResult {
        guard !isLoggingIn else {
            throw MatrixSSOError.loginInProgress
        }

        isLoggingIn = true
        lastError = nil

        defer {
            isLoggingIn = false
        }

        #if DEBUG
        print("[MatrixSSO] Starting SSO login flow")
        #endif

        // Check SSO availability first
        let available = try await checkSSOAvailable()
        guard available else {
            throw MatrixSSOError.ssoNotSupported
        }

        // Build SSO redirect URL
        let ssoURL = buildSSORedirectURL()

        guard let url = URL(string: ssoURL) else {
            throw MatrixSSOError.invalidURL(ssoURL)
        }

        #if DEBUG
        print("[MatrixSSO] Opening SSO URL: \(ssoURL)")
        #endif

        // Use ASWebAuthenticationSession for secure SSO
        return try await withCheckedThrowingContinuation { continuation in
            self.loginContinuation = continuation

            // Extract callback scheme from callback URL
            let callbackScheme = URL(string: self.ssoCallbackURL)?.scheme ?? "nova-staging"

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                guard let self = self else { return }

                Task { @MainActor in
                    if let error = error {
                        if let authError = error as? ASWebAuthenticationSessionError,
                           authError.code == .canceledLogin {
                            self.loginContinuation?.resume(throwing: MatrixSSOError.userCancelled)
                        } else {
                            self.loginContinuation?.resume(throwing: MatrixSSOError.authSessionError(error.localizedDescription))
                        }
                        self.loginContinuation = nil
                        return
                    }

                    guard let callbackURL = callbackURL else {
                        self.loginContinuation?.resume(throwing: MatrixSSOError.noCallbackURL)
                        self.loginContinuation = nil
                        return
                    }

                    // Handle the callback URL
                    do {
                        let result = try await self.handleSSOCallback(url: callbackURL)
                        self.loginContinuation?.resume(returning: result)
                    } catch {
                        self.loginContinuation?.resume(throwing: error)
                    }
                    self.loginContinuation = nil
                }
            }

            // Configure presentation
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = MatrixSSOPresentationProvider.shared

            self.authSession = session

            // Start the session
            if !session.start() {
                self.loginContinuation?.resume(throwing: MatrixSSOError.authSessionFailed)
                self.loginContinuation = nil
            }
        }
    }

    /// Build the SSO redirect URL
    private func buildSSORedirectURL() -> String {
        // Encode the callback URL
        let encodedCallback = ssoCallbackURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ssoCallbackURL

        return "\(homeserverURL)/_matrix/client/v3/login/sso/redirect?redirectUrl=\(encodedCallback)"
    }

    // MARK: - SSO Callback Handling

    /// Handle SSO callback URL and extract loginToken
    /// URL format: nova-staging://matrix-sso-callback?loginToken=xxx
    func handleSSOCallback(url: URL) async throws -> MatrixSSOLoginResult {
        #if DEBUG
        print("[MatrixSSO] Handling callback URL: \(url)")
        #endif

        // Parse URL components
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw MatrixSSOError.invalidCallbackURL(url.absoluteString)
        }

        // Extract loginToken parameter
        guard let loginToken = components.queryItems?.first(where: { $0.name == "loginToken" })?.value else {
            throw MatrixSSOError.missingLoginToken
        }

        #if DEBUG
        print("[MatrixSSO] Extracted loginToken: \(loginToken.prefix(10))...")
        #endif

        // Exchange login token for access token
        return try await exchangeLoginToken(token: loginToken)
    }

    /// Handle incoming URL (called from SceneDelegate/AppDelegate)
    /// Returns true if URL was handled as Matrix SSO callback
    func handleOpenURL(_ url: URL) -> Bool {
        // Check if this is our SSO callback URL
        guard let scheme = url.scheme,
              (scheme == "nova-staging" || scheme == "nova"),
              url.host == "matrix-sso-callback" else {
            return false
        }

        #if DEBUG
        print("[MatrixSSO] Received SSO callback URL")
        #endif

        // If we have an active login continuation, the ASWebAuthenticationSession
        // will handle it automatically. This method is for deep link handling.
        return true
    }

    // MARK: - Token Exchange

    /// Exchange SSO loginToken for Matrix access_token
    /// Uses m.login.token authentication type
    func exchangeLoginToken(token: String) async throws -> MatrixSSOLoginResult {
        #if DEBUG
        print("[MatrixSSO] Exchanging login token for access token")
        #endif

        let loginEndpoint = "\(homeserverURL)/_matrix/client/v3/login"

        guard let url = URL(string: loginEndpoint) else {
            throw MatrixSSOError.invalidURL(loginEndpoint)
        }

        // Build login request with token
        let loginRequest = MatrixTokenLoginRequest(
            type: "m.login.token",
            token: token,
            initialDeviceDisplayName: await getDeviceDisplayName()
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Note: Don't use .convertToSnakeCase as CodingKeys already handles snake_case mapping
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(loginRequest)

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MatrixSSOError.networkError("Invalid response type")
            }

            // Check for error response
            if httpResponse.statusCode != 200 {
                // Try to parse Matrix error response
                if let errorResponse = try? JSONDecoder().decode(MatrixErrorResponse.self, from: data) {
                    throw MatrixSSOError.matrixError(errorResponse.errcode, errorResponse.error)
                }
                throw MatrixSSOError.serverError(httpResponse.statusCode, "Token exchange failed")
            }

            // Parse successful login response
            // Note: Don't use .convertFromSnakeCase as CodingKeys already handles snake_case mapping
            let decoder = JSONDecoder()
            let loginResponse = try decoder.decode(MatrixLoginResponse.self, from: data)

            #if DEBUG
            print("[MatrixSSO] Login successful!")
            print("[MatrixSSO] User ID: \(loginResponse.userId)")
            print("[MatrixSSO] Device ID: \(loginResponse.deviceId)")
            #endif

            // Save credentials to Keychain
            saveCredentials(loginResponse)

            return MatrixSSOLoginResult(
                userId: loginResponse.userId,
                accessToken: loginResponse.accessToken,
                deviceId: loginResponse.deviceId,
                homeServer: loginResponse.homeServer ?? homeserverURL,
                wellKnown: loginResponse.wellKnown
            )

        } catch let error as MatrixSSOError {
            self.lastError = error
            throw error
        } catch {
            let ssoError = MatrixSSOError.networkError(error.localizedDescription)
            self.lastError = ssoError
            throw ssoError
        }
    }

    // MARK: - Credential Storage

    /// Save Matrix credentials to Keychain
    private func saveCredentials(_ response: MatrixLoginResponse) {
        // Save access token
        _ = keychain.save(response.accessToken, for: .matrixAccessToken)

        // Save user ID
        _ = keychain.save(response.userId, for: .matrixUserId)

        // Save device ID
        _ = keychain.save(response.deviceId, for: .matrixDeviceId)

        // Save homeserver URL
        if let homeServer = response.homeServer {
            _ = keychain.save(homeServer, for: .matrixHomeserver)
        } else {
            _ = keychain.save(homeserverURL, for: .matrixHomeserver)
        }

        #if DEBUG
        print("[MatrixSSO] Credentials saved to Keychain")
        #endif
    }

    /// Load stored Matrix credentials
    func loadStoredCredentials() -> MatrixSSOLoginResult? {
        guard let accessToken = keychain.get(.matrixAccessToken),
              let userId = keychain.get(.matrixUserId),
              let deviceId = keychain.get(.matrixDeviceId) else {
            return nil
        }

        let homeServer = keychain.get(.matrixHomeserver) ?? homeserverURL

        return MatrixSSOLoginResult(
            userId: userId,
            accessToken: accessToken,
            deviceId: deviceId,
            homeServer: homeServer,
            wellKnown: nil
        )
    }

    /// Check if Matrix credentials are stored
    var hasStoredCredentials: Bool {
        keychain.get(.matrixAccessToken) != nil &&
        keychain.get(.matrixUserId) != nil
    }

    /// Clear stored Matrix credentials
    func clearCredentials() {
        keychain.delete(.matrixAccessToken)
        keychain.delete(.matrixUserId)
        keychain.delete(.matrixDeviceId)
        keychain.delete(.matrixHomeserver)

        #if DEBUG
        print("[MatrixSSO] Credentials cleared from Keychain")
        #endif
    }

    // MARK: - Helpers

    /// Get device display name for Matrix registration
    private func getDeviceDisplayName() async -> String {
        #if os(iOS)
        return await MainActor.run {
            "\(UIDevice.current.name) (Nova iOS)"
        }
        #else
        return "Nova iOS"
        #endif
    }

    /// Cancel any ongoing SSO login
    func cancelLogin() {
        authSession?.cancel()
        authSession = nil

        if let continuation = loginContinuation {
            continuation.resume(throwing: MatrixSSOError.userCancelled)
            loginContinuation = nil
        }

        isLoggingIn = false

        #if DEBUG
        print("[MatrixSSO] Login cancelled")
        #endif
    }
}

// MARK: - Presentation Context Provider

private class MatrixSSOPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = MatrixSSOPresentationProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the key window for presentation
        #if os(iOS)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        // iOS 26+: Create window with window scene instead of empty init
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return UIWindow(windowScene: windowScene)
        }
        return UIWindow(frame: UIScreen.main.bounds)
        #else
        return ASPresentationAnchor()
        #endif
    }
}

// MARK: - SSO Configuration
// Note: Reuses MatrixConfiguration from MatrixService.swift to avoid duplicate definitions

struct MatrixSSOConfiguration {

    /// Get homeserver URL based on environment (delegates to MatrixConfiguration)
    static var homeserverURL: String {
        MatrixConfiguration.homeserverURL
    }

    /// Get SSO callback URL based on environment (delegates to MatrixConfiguration)
    static var ssoCallbackURL: String {
        MatrixConfiguration.ssoCallbackURL
    }

    /// URL scheme for deep linking
    static var urlScheme: String {
        switch APIConfig.current {
        case .development, .staging:
            return "nova-staging"
        case .production:
            return "nova"
        }
    }
}

// MARK: - SSO Result

struct MatrixSSOLoginResult {
    let userId: String          // e.g., @nova-uuid:matrix.nova.app
    let accessToken: String     // Matrix access token
    let deviceId: String        // Matrix device ID
    let homeServer: String      // Homeserver URL
    let wellKnown: MatrixWellKnown?  // Server discovery info (optional)
}

// MARK: - API Models

/// Matrix login flows response
struct MatrixLoginFlowsResponse: Codable {
    let flows: [MatrixLoginFlow]
}

struct MatrixLoginFlow: Codable {
    let type: String
    let identityProviders: [MatrixIdentityProvider]?

    enum CodingKeys: String, CodingKey {
        case type
        case identityProviders = "identity_providers"
    }
}

struct MatrixIdentityProvider: Codable {
    let id: String
    let name: String
    let icon: String?
    let brand: String?
}

/// Matrix token login request
struct MatrixTokenLoginRequest: Codable {
    let type: String
    let token: String
    let initialDeviceDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case type
        case token
        case initialDeviceDisplayName = "initial_device_display_name"
    }
}

/// Matrix login response
struct MatrixLoginResponse: Codable {
    let userId: String
    let accessToken: String
    let deviceId: String
    let homeServer: String?
    let wellKnown: MatrixWellKnown?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case accessToken = "access_token"
        case deviceId = "device_id"
        case homeServer = "home_server"
        case wellKnown = "well_known"
    }
}

/// Matrix server discovery info
struct MatrixWellKnown: Codable {
    let homeserver: MatrixHomeserverInfo?
    let identityServer: MatrixIdentityServerInfo?

    enum CodingKeys: String, CodingKey {
        case homeserver = "m.homeserver"
        case identityServer = "m.identity_server"
    }
}

struct MatrixHomeserverInfo: Codable {
    let baseUrl: String

    enum CodingKeys: String, CodingKey {
        case baseUrl = "base_url"
    }
}

struct MatrixIdentityServerInfo: Codable {
    let baseUrl: String

    enum CodingKeys: String, CodingKey {
        case baseUrl = "base_url"
    }
}

/// Matrix error response
struct MatrixErrorResponse: Codable {
    let errcode: String
    let error: String
}

// MARK: - SSO Errors

enum MatrixSSOError: Error, LocalizedError {
    case invalidURL(String)
    case networkError(String)
    case serverError(Int, String)
    case ssoNotSupported
    case loginInProgress
    case userCancelled
    case authSessionError(String)
    case authSessionFailed
    case noCallbackURL
    case invalidCallbackURL(String)
    case missingLoginToken
    case matrixError(String, String)  // errcode, error message
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .ssoNotSupported:
            return "SSO login is not supported by this Matrix homeserver"
        case .loginInProgress:
            return "A login is already in progress"
        case .userCancelled:
            return "Login was cancelled"
        case .authSessionError(let reason):
            return "Authentication error: \(reason)"
        case .authSessionFailed:
            return "Failed to start authentication session"
        case .noCallbackURL:
            return "No callback URL received"
        case .invalidCallbackURL(let url):
            return "Invalid callback URL: \(url)"
        case .missingLoginToken:
            return "No login token in callback URL"
        case .matrixError(let errcode, let message):
            return "Matrix error [\(errcode)]: \(message)"
        case .tokenExchangeFailed(let reason):
            return "Token exchange failed: \(reason)"
        }
    }

    /// Whether this error is recoverable and user can retry
    var isRecoverable: Bool {
        switch self {
        case .networkError, .serverError, .authSessionFailed:
            return true
        case .userCancelled, .loginInProgress, .ssoNotSupported:
            return false
        default:
            return false
        }
    }
}
