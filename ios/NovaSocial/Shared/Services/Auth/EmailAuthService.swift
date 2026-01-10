import Foundation
import UIKit

// MARK: - Email Auth Service

/// Handles email address authentication flows
/// Communicates with backend identity-service for email verification
class EmailAuthService {
    static let shared = EmailAuthService()

    private init() {}

    // MARK: - Device Info (session tracking)

    private struct DeviceInfo {
        let deviceId: String
        let deviceName: String
        let deviceType: String
        let osVersion: String
        let userAgent: String
    }

    private func getDeviceInfo() async -> DeviceInfo {
        await MainActor.run {
            let device = UIDevice.current
            let deviceId = device.identifierForVendor?.uuidString ?? UUID().uuidString
            let deviceName = device.name
            let systemName = device.systemName
            let systemVersion = device.systemVersion
            let deviceModel = device.model

            let deviceType: String
            switch device.userInterfaceIdiom {
            case .phone, .pad:
                deviceType = "iOS"
            case .mac:
                deviceType = "macOS"
            default:
                deviceType = "iOS"
            }

            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let userAgent = "NovaSocial/\(appVersion) (\(deviceModel))"

            return DeviceInfo(
                deviceId: deviceId,
                deviceName: deviceName,
                deviceType: deviceType,
                osVersion: "\(systemName) \(systemVersion)",
                userAgent: userAgent
            )
        }
    }

    // MARK: - Response Types

    struct SendCodeResponse: Codable {
        let success: Bool
        let message: String?
        let expiresIn: Int?  // seconds until code expires

        enum CodingKeys: String, CodingKey {
            case success
            case message
            case expiresIn = "expires_in"
        }
    }

    struct VerifyCodeResponse: Codable {
        let success: Bool
        let verificationToken: String?  // Token to use for registration
        let message: String?

        enum CodingKeys: String, CodingKey {
            case success
            case verificationToken = "verification_token"
            case message
        }
    }

    struct EmailRegisterResponse: Codable {
        let userId: String
        let token: String
        let refreshToken: String?
        let user: UserProfile?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case token
            case refreshToken = "refresh_token"
            case user
        }
    }

    // MARK: - API Methods

    /// Send verification code to email address
    /// - Parameter email: Email address to send code to
    /// - Returns: Response indicating success and code expiration time
    func sendVerificationCode(email: String) async throws -> SendCodeResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/email/send-code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmailAuthError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 429 {
            throw EmailAuthError.rateLimited
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw EmailAuthError.serverError(errorResponse.message ?? "Failed to send code")
            }
            throw EmailAuthError.sendCodeFailed
        }

        return try JSONDecoder().decode(SendCodeResponse.self, from: data)
    }

    /// Verify the code sent to email address
    /// - Parameters:
    ///   - email: Email address
    ///   - code: 6-digit verification code
    /// - Returns: Response with verification token for registration
    func verifyCode(email: String, code: String) async throws -> VerifyCodeResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/email/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "code": code
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmailAuthError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 400 {
            throw EmailAuthError.invalidCode
        }

        if httpResponse.statusCode == 410 {
            throw EmailAuthError.codeExpired
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw EmailAuthError.serverError(errorResponse.message ?? "Verification failed")
            }
            throw EmailAuthError.verificationFailed
        }

        return try JSONDecoder().decode(VerifyCodeResponse.self, from: data)
    }

    /// Register new user with verified email
    /// - Parameters:
    ///   - email: Verified email address
    ///   - verificationToken: Token from successful verification
    ///   - username: Desired username
    ///   - password: Password for the account
    ///   - displayName: Optional display name
    /// - Returns: Registration response with auth tokens
    func registerWithEmail(
        email: String,
        verificationToken: String,
        username: String,
        password: String,
        displayName: String? = nil
    ) async throws -> EmailRegisterResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/email/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let deviceInfo = await getDeviceInfo()

        var body: [String: Any] = [
            "email": email,
            "verification_token": verificationToken,
            "username": username,
            "password": password,
            // Device/session tracking
            "device_id": deviceInfo.deviceId,
            "device_name": deviceInfo.deviceName,
            "device_type": deviceInfo.deviceType,
            "os_version": deviceInfo.osVersion,
            "user_agent": deviceInfo.userAgent
        ]

        if let displayName = displayName, !displayName.isEmpty {
            body["display_name"] = displayName
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmailAuthError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 409 {
            throw EmailAuthError.emailAlreadyRegistered
        }

        if httpResponse.statusCode != 200 && httpResponse.statusCode != 201 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw EmailAuthError.serverError(errorResponse.message ?? "Registration failed")
            }
            throw EmailAuthError.registrationFailed
        }

        return try JSONDecoder().decode(EmailRegisterResponse.self, from: data)
    }

    /// Login with email (for existing users)
    /// - Parameters:
    ///   - email: Email address
    ///   - verificationToken: Token from successful verification
    /// - Returns: Login response with auth tokens
    func loginWithEmail(
        email: String,
        verificationToken: String
    ) async throws -> EmailRegisterResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/email/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let deviceInfo = await getDeviceInfo()

        let body: [String: Any] = [
            "email": email,
            "verification_token": verificationToken,
            // Device/session tracking
            "device_id": deviceInfo.deviceId,
            "device_name": deviceInfo.deviceName,
            "device_type": deviceInfo.deviceType,
            "os_version": deviceInfo.osVersion,
            "user_agent": deviceInfo.userAgent
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmailAuthError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 404 {
            throw EmailAuthError.emailNotRegistered
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw EmailAuthError.serverError(errorResponse.message ?? "Login failed")
            }
            throw EmailAuthError.loginFailed
        }

        return try JSONDecoder().decode(EmailRegisterResponse.self, from: data)
    }
}

// MARK: - Email Auth Errors

enum EmailAuthError: LocalizedError {
    case sendCodeFailed
    case invalidCode
    case codeExpired
    case verificationFailed
    case registrationFailed
    case loginFailed
    case emailAlreadyRegistered
    case emailNotRegistered
    case rateLimited
    case networkError(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .sendCodeFailed:
            return "Failed to send verification code"
        case .invalidCode:
            return "Invalid verification code"
        case .codeExpired:
            return "Verification code has expired"
        case .verificationFailed:
            return "Email verification failed"
        case .registrationFailed:
            return "Registration failed"
        case .loginFailed:
            return "Login failed"
        case .emailAlreadyRegistered:
            return "This email is already registered"
        case .emailNotRegistered:
            return "No account found with this email"
        case .rateLimited:
            return "Too many attempts. Please try again later"
        case .networkError(let message):
            return "Network error: \(message)"
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
