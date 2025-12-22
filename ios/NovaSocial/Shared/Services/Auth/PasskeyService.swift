import Foundation
import AuthenticationServices
import os

// MARK: - Passkey Service

/// Handles WebAuthn/FIDO2 Passkey authentication flows
/// Uses iOS AuthenticationServices framework for platform authenticator
/// Communicates with backend identity-service for challenge/verification
@available(iOS 16.0, *)
class PasskeyService: NSObject {
    static let shared = PasskeyService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NovaSocial", category: "PasskeyService")

    // WebAuthn Relying Party ID - must match backend configuration and AASA domain
    // AASA file hosted at aasa.icered.com/.well-known/apple-app-site-association
    private let relyingPartyIdentifier = "aasa.icered.com"

    // Continuations for async/await bridge
    private var registrationContinuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialRegistration, Error>?
    private var authenticationContinuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialAssertion, Error>?

    // MARK: - Error Types

    enum PasskeyError: LocalizedError {
        case notSupported
        case registrationFailed(String)
        case authenticationFailed(String)
        case challengeRequestFailed
        case verificationFailed(String)
        case cancelled
        case noCredentials
        case serverError(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notSupported:
                return "Passkey is not supported on this device"
            case .registrationFailed(let message):
                return "Passkey registration failed: \(message)"
            case .authenticationFailed(let message):
                return "Passkey authentication failed: \(message)"
            case .challengeRequestFailed:
                return "Failed to get passkey challenge from server"
            case .verificationFailed(let message):
                return "Passkey verification failed: \(message)"
            case .cancelled:
                return "Passkey operation was cancelled"
            case .noCredentials:
                return "No passkey credentials found"
            case .serverError(let message):
                return "Server error: \(message)"
            case .invalidResponse:
                return "Invalid response from server"
            }
        }
    }

    // MARK: - Response Types

    struct StartRegistrationResponse: Codable {
        let challengeId: String
        let options: String

        enum CodingKeys: String, CodingKey {
            case challengeId = "challenge_id"
            case options
        }
    }

    struct CompleteRegistrationResponse: Codable {
        let credentialId: String
        let credentialName: String?

        enum CodingKeys: String, CodingKey {
            case credentialId = "credential_id"
            case credentialName = "credential_name"
        }
    }

    struct StartAuthenticationResponse: Codable {
        let challengeId: String
        let options: String

        enum CodingKeys: String, CodingKey {
            case challengeId = "challenge_id"
            case options
        }
    }

    struct CompleteAuthenticationResponse: Codable {
        let userId: String
        let token: String
        let refreshToken: String?
        let expiresIn: Int64
        let credentialId: String
        let user: PasskeyUserProfile?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case token
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case credentialId = "credential_id"
            case user
        }
    }

    struct PasskeyUserProfile: Codable {
        let id: String
        let username: String
        let email: String?
    }

    struct PasskeyInfo: Codable, Identifiable {
        let id: String
        let credentialName: String?
        let deviceType: String?
        let osVersion: String?
        let backupEligible: Bool
        let backupState: Bool
        let transports: [String]
        let createdAt: Int64
        let lastUsedAt: Int64?
        let isActive: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case credentialName = "credential_name"
            case deviceType = "device_type"
            case osVersion = "os_version"
            case backupEligible = "backup_eligible"
            case backupState = "backup_state"
            case transports
            case createdAt = "created_at"
            case lastUsedAt = "last_used_at"
            case isActive = "is_active"
        }
    }

    struct ListPasskeysResponse: Codable {
        let passkeys: [PasskeyInfo]
    }

    // MARK: - WebAuthn Options Parsing

    // Wrapper for webauthn-rs response that wraps options in "publicKey"
    private struct WebAuthnCreationOptionsWrapper: Codable {
        let publicKey: WebAuthnCreationOptions
    }

    private struct WebAuthnCreationOptions: Codable {
        let rp: RelyingParty
        let user: WebAuthnUser
        let challenge: String
        let pubKeyCredParams: [PubKeyCredParam]
        let timeout: Int?
        let excludeCredentials: [ExcludeCredential]?
        let authenticatorSelection: AuthenticatorSelection?

        struct RelyingParty: Codable {
            let name: String
            let id: String
        }

        struct WebAuthnUser: Codable {
            let id: String
            let name: String
            let displayName: String
        }

        struct PubKeyCredParam: Codable {
            let type: String
            let alg: Int
        }

        struct ExcludeCredential: Codable {
            let id: String
            let type: String
        }

        struct AuthenticatorSelection: Codable {
            let authenticatorAttachment: String?
            let residentKey: String?
            let userVerification: String?
        }
    }

    // Wrapper for webauthn-rs response that wraps options in "publicKey"
    private struct WebAuthnRequestOptionsWrapper: Codable {
        let publicKey: WebAuthnRequestOptions
    }

    private struct WebAuthnRequestOptions: Codable {
        let challenge: String
        let timeout: Int?
        let rpId: String?
        let allowCredentials: [AllowCredential]?
        let userVerification: String?

        struct AllowCredential: Codable {
            let id: String
            let type: String
            let transports: [String]?
        }
    }

    // MARK: - Registration Flow

    /// Start passkey registration for an authenticated user
    /// Returns credential ID on success
    @MainActor
    func registerPasskey(
        credentialName: String? = nil,
        anchor: ASPresentationAnchor? = nil
    ) async throws -> CompleteRegistrationResponse {
        logger.info("Starting passkey registration")

        // 1. Request challenge from backend
        let startResponse = try await requestRegistrationChallenge(credentialName: credentialName)
        logger.debug("Received registration challenge: \(startResponse.challengeId)")

        // 2. Parse options and create platform credential
        let options = try parseCreationOptions(startResponse.options)

        // 3. Perform registration ceremony with iOS authenticator
        let registration = try await performRegistration(options: options, anchor: anchor)

        // 4. Complete registration with backend
        let response = try await completeRegistration(
            challengeId: startResponse.challengeId,
            registration: registration,
            credentialName: credentialName
        )

        logger.info("Passkey registration completed: \(response.credentialId)")
        return response
    }

    // MARK: - Authentication Flow

    /// Authenticate with passkey
    /// Returns auth tokens and user info on success
    @MainActor
    func authenticateWithPasskey(
        userId: String? = nil,
        anchor: ASPresentationAnchor? = nil
    ) async throws -> CompleteAuthenticationResponse {
        logger.info("Starting passkey authentication")

        // 1. Request challenge from backend
        let startResponse = try await requestAuthenticationChallenge(userId: userId)
        logger.debug("Received authentication challenge: \(startResponse.challengeId)")

        // 2. Parse options
        let options = try parseRequestOptions(startResponse.options)

        // 3. Perform authentication ceremony with iOS authenticator
        let assertion = try await performAuthentication(options: options, anchor: anchor)

        // 4. Complete authentication with backend
        let response = try await completeAuthentication(
            challengeId: startResponse.challengeId,
            assertion: assertion
        )

        logger.info("Passkey authentication completed for user: \(response.userId)")
        return response
    }

    /// Authenticate with passkey using AutoFill (conditional UI)
    /// Call this when LoginView appears to enable passkey suggestion in keyboard
    @MainActor
    func authenticateWithAutoFill(
        textField: UITextField? = nil
    ) async throws -> CompleteAuthenticationResponse {
        logger.info("Starting passkey AutoFill authentication")

        // 1. Request challenge from backend (no user ID for discoverable flow)
        let startResponse = try await requestAuthenticationChallenge(userId: nil)
        logger.debug("Received AutoFill authentication challenge: \(startResponse.challengeId)")

        // 2. Parse options
        let options = try parseRequestOptions(startResponse.options)

        // 3. Perform AutoFill authentication
        let assertion = try await performAutoFillAuthentication(options: options)

        // 4. Complete authentication with backend
        let response = try await completeAuthentication(
            challengeId: startResponse.challengeId,
            assertion: assertion
        )

        logger.info("Passkey AutoFill authentication completed for user: \(response.userId)")
        return response
    }

    // MARK: - Passkey Management

    /// List user's registered passkeys
    func listPasskeys() async throws -> [PasskeyInfo] {
        guard let token = KeychainService.shared.get(.authToken) else {
            throw PasskeyError.authenticationFailed("Not authenticated")
        }

        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/passkey/list")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PasskeyError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            throw PasskeyError.serverError("Failed to list passkeys: \(httpResponse.statusCode)")
        }

        let listResponse = try JSONDecoder().decode(ListPasskeysResponse.self, from: data)
        return listResponse.passkeys
    }

    /// Revoke a passkey credential
    func revokePasskey(credentialId: String) async throws {
        guard let token = KeychainService.shared.get(.authToken) else {
            throw PasskeyError.authenticationFailed("Not authenticated")
        }

        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/passkey/\(credentialId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PasskeyError.invalidResponse
        }

        if httpResponse.statusCode != 204 {
            throw PasskeyError.serverError("Failed to revoke passkey: \(httpResponse.statusCode)")
        }

        logger.info("Passkey revoked: \(credentialId)")
    }

    /// Rename a passkey credential
    func renamePasskey(credentialId: String, newName: String) async throws {
        guard let token = KeychainService.shared.get(.authToken) else {
            throw PasskeyError.authenticationFailed("Not authenticated")
        }

        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/passkey/\(credentialId)/rename")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = ["new_name": newName]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PasskeyError.invalidResponse
        }

        if httpResponse.statusCode != 204 {
            throw PasskeyError.serverError("Failed to rename passkey: \(httpResponse.statusCode)")
        }

        logger.info("Passkey renamed: \(credentialId) -> \(newName)")
    }

    // MARK: - Private Methods - API Communication

    private func requestRegistrationChallenge(credentialName: String?) async throws -> StartRegistrationResponse {
        guard let token = KeychainService.shared.get(.authToken) else {
            throw PasskeyError.authenticationFailed("Not authenticated")
        }

        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/passkey/register/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [:]
        if let name = credentialName {
            body["credential_name"] = name
        }
        let deviceInfo = await MainActor.run { (UIDevice.current.model, UIDevice.current.systemVersion) }
        body["device_type"] = deviceInfo.0
        body["os_version"] = deviceInfo.1
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PasskeyError.challengeRequestFailed
        }

        if httpResponse.statusCode != 200 {
            if let errorData = String(data: data, encoding: .utf8) {
                logger.error("Registration challenge failed: \(errorData)")
            }
            throw PasskeyError.challengeRequestFailed
        }

        return try JSONDecoder().decode(StartRegistrationResponse.self, from: data)
    }

    private func requestAuthenticationChallenge(userId: String?) async throws -> StartAuthenticationResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/passkey/authenticate/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [:]
        if let userId = userId {
            body["user_id"] = userId
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PasskeyError.challengeRequestFailed
        }

        if httpResponse.statusCode != 200 {
            if let errorData = String(data: data, encoding: .utf8) {
                logger.error("Authentication challenge failed: \(errorData)")
            }
            throw PasskeyError.challengeRequestFailed
        }

        return try JSONDecoder().decode(StartAuthenticationResponse.self, from: data)
    }

    private func completeRegistration(
        challengeId: String,
        registration: ASAuthorizationPlatformPublicKeyCredentialRegistration,
        credentialName: String?
    ) async throws -> CompleteRegistrationResponse {
        guard let token = KeychainService.shared.get(.authToken) else {
            throw PasskeyError.authenticationFailed("Not authenticated")
        }

        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/passkey/register/complete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Build attestation response JSON
        let attestationResponse = buildAttestationResponse(registration)

        var body: [String: Any] = [
            "challenge_id": challengeId,
            "attestation_response": attestationResponse
        ]
        if let name = credentialName {
            body["credential_name"] = name
        }
        let deviceInfo = await MainActor.run { (UIDevice.current.model, UIDevice.current.systemVersion) }
        body["device_type"] = deviceInfo.0
        body["os_version"] = deviceInfo.1

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PasskeyError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorData = String(data: data, encoding: .utf8) {
                logger.error("Registration completion failed: \(errorData)")
            }
            throw PasskeyError.registrationFailed("Server rejected attestation")
        }

        return try JSONDecoder().decode(CompleteRegistrationResponse.self, from: data)
    }

    private func completeAuthentication(
        challengeId: String,
        assertion: ASAuthorizationPlatformPublicKeyCredentialAssertion
    ) async throws -> CompleteAuthenticationResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/passkey/authenticate/complete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build assertion response JSON
        let assertionResponse = buildAssertionResponse(assertion)

        let body: [String: Any] = [
            "challenge_id": challengeId,
            "assertion_response": assertionResponse
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PasskeyError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorData = String(data: data, encoding: .utf8) {
                logger.error("Authentication completion failed: \(errorData)")
            }
            throw PasskeyError.authenticationFailed("Server rejected assertion")
        }

        return try JSONDecoder().decode(CompleteAuthenticationResponse.self, from: data)
    }

    // MARK: - Private Methods - Options Parsing

    private func parseCreationOptions(_ optionsJson: String) throws -> WebAuthnCreationOptions {
        guard let data = optionsJson.data(using: .utf8) else {
            throw PasskeyError.invalidResponse
        }
        // webauthn-rs wraps options in "publicKey" - unwrap it
        let wrapper = try JSONDecoder().decode(WebAuthnCreationOptionsWrapper.self, from: data)
        return wrapper.publicKey
    }

    private func parseRequestOptions(_ optionsJson: String) throws -> WebAuthnRequestOptions {
        guard let data = optionsJson.data(using: .utf8) else {
            throw PasskeyError.invalidResponse
        }
        // webauthn-rs wraps options in "publicKey" - unwrap it
        let wrapper = try JSONDecoder().decode(WebAuthnRequestOptionsWrapper.self, from: data)
        return wrapper.publicKey
    }

    // MARK: - Private Methods - Credential Building

    private func buildAttestationResponse(_ registration: ASAuthorizationPlatformPublicKeyCredentialRegistration) -> String {
        let credentialId = registration.credentialID.base64URLEncodedString()
        let attestationObject = registration.rawAttestationObject?.base64URLEncodedString() ?? ""
        let clientDataJSON = registration.rawClientDataJSON.base64URLEncodedString()

        let response: [String: Any] = [
            "id": credentialId,
            "rawId": credentialId,
            "type": "public-key",
            "response": [
                "attestationObject": attestationObject,
                "clientDataJSON": clientDataJSON
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: response),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }

    private func buildAssertionResponse(_ assertion: ASAuthorizationPlatformPublicKeyCredentialAssertion) -> String {
        let credentialId = assertion.credentialID.base64URLEncodedString()
        let authenticatorData = assertion.rawAuthenticatorData.base64URLEncodedString()
        let clientDataJSON = assertion.rawClientDataJSON.base64URLEncodedString()
        let signature = assertion.signature.base64URLEncodedString()
        let userHandle = assertion.userID.base64URLEncodedString()

        let response: [String: Any] = [
            "id": credentialId,
            "rawId": credentialId,
            "type": "public-key",
            "response": [
                "authenticatorData": authenticatorData,
                "clientDataJSON": clientDataJSON,
                "signature": signature,
                "userHandle": userHandle
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: response),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }

    // MARK: - Private Methods - iOS Authenticator

    @MainActor
    private func performRegistration(
        options: WebAuthnCreationOptions,
        anchor: ASPresentationAnchor?
    ) async throws -> ASAuthorizationPlatformPublicKeyCredentialRegistration {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)

        // Decode challenge from base64url
        guard let challengeData = Data(base64URLEncoded: options.challenge),
              let userIdData = Data(base64URLEncoded: options.user.id) else {
            throw PasskeyError.invalidResponse
        }

        let request = provider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: options.user.name,
            userID: userIdData
        )

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.registrationContinuation = continuation
            controller.performRequests()
        }
    }

    @MainActor
    private func performAuthentication(
        options: WebAuthnRequestOptions,
        anchor: ASPresentationAnchor?
    ) async throws -> ASAuthorizationPlatformPublicKeyCredentialAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)

        guard let challengeData = Data(base64URLEncoded: options.challenge) else {
            throw PasskeyError.invalidResponse
        }

        // Build allowed credentials if provided
        let allowedCredentials: [ASAuthorizationPlatformPublicKeyCredentialDescriptor]?
        if let allowCreds = options.allowCredentials {
            allowedCredentials = allowCreds.compactMap { cred in
                guard let credIdData = Data(base64URLEncoded: cred.id) else { return nil }
                return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: credIdData)
            }
        } else {
            allowedCredentials = nil
        }

        let request = provider.createCredentialAssertionRequest(challenge: challengeData)
        if let allowedCreds = allowedCredentials, !allowedCreds.isEmpty {
            request.allowedCredentials = allowedCreds
        }

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.authenticationContinuation = continuation
            controller.performRequests()
        }
    }

    @MainActor
    private func performAutoFillAuthentication(
        options: WebAuthnRequestOptions
    ) async throws -> ASAuthorizationPlatformPublicKeyCredentialAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)

        guard let challengeData = Data(base64URLEncoded: options.challenge) else {
            throw PasskeyError.invalidResponse
        }

        let request = provider.createCredentialAssertionRequest(challenge: challengeData)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.authenticationContinuation = continuation
            // Use performAutoFillAssistedRequests for conditional UI
            controller.performAutoFillAssistedRequests()
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

@available(iOS 16.0, *)
extension PasskeyService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        switch authorization.credential {
        case let registration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            logger.debug("Passkey registration credential received")
            registrationContinuation?.resume(returning: registration)
            registrationContinuation = nil

        case let assertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            logger.debug("Passkey assertion credential received")
            authenticationContinuation?.resume(returning: assertion)
            authenticationContinuation = nil

        default:
            logger.warning("Unknown credential type received")
            registrationContinuation?.resume(throwing: PasskeyError.invalidResponse)
            authenticationContinuation?.resume(throwing: PasskeyError.invalidResponse)
            registrationContinuation = nil
            authenticationContinuation = nil
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        logger.error("Passkey operation failed: \(error.localizedDescription)")

        let passkeyError: PasskeyError
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                passkeyError = .cancelled
            case .failed:
                passkeyError = .authenticationFailed(authError.localizedDescription)
            case .invalidResponse:
                passkeyError = .invalidResponse
            case .notHandled:
                passkeyError = .noCredentials
            case .notInteractive:
                passkeyError = .authenticationFailed("User interaction required")
            case .unknown:
                passkeyError = .authenticationFailed("Unknown error")
            case .matchedExcludedCredential:
                passkeyError = .registrationFailed("This passkey is already registered")
            @unknown default:
                passkeyError = .authenticationFailed(authError.localizedDescription)
            }
        } else {
            passkeyError = .authenticationFailed(error.localizedDescription)
        }

        registrationContinuation?.resume(throwing: passkeyError)
        authenticationContinuation?.resume(throwing: passkeyError)
        registrationContinuation = nil
        authenticationContinuation = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

@available(iOS 16.0, *)
extension PasskeyService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the key window
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Base64URL Extensions

private extension Data {
    /// Create Data from base64url encoded string
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(contentsOf: String(repeating: "=", count: 4 - remainder))
        }

        self.init(base64Encoded: base64)
    }

    /// Convert Data to base64url encoded string
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
