import Foundation

// MARK: - Phone Auth Service

/// Handles phone number authentication flows
/// Communicates with backend identity-service for SMS verification
class PhoneAuthService {
    static let shared = PhoneAuthService()

    private init() {}

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

    struct PhoneRegisterResponse: Codable {
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

    /// Send verification code to phone number
    /// - Parameter phoneNumber: Phone number in E.164 format (e.g., +14155551234)
    /// - Returns: Response indicating success and code expiration time
    func sendVerificationCode(phoneNumber: String) async throws -> SendCodeResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/phone/send-code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "phone_number": phoneNumber
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhoneAuthError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 429 {
            throw PhoneAuthError.rateLimited
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw PhoneAuthError.serverError(errorResponse.message ?? "Failed to send code")
            }
            throw PhoneAuthError.sendCodeFailed
        }

        return try JSONDecoder().decode(SendCodeResponse.self, from: data)
    }

    /// Verify the code sent to phone number
    /// - Parameters:
    ///   - phoneNumber: Phone number in E.164 format
    ///   - code: 6-digit verification code
    /// - Returns: Response with verification token for registration
    func verifyCode(phoneNumber: String, code: String) async throws -> VerifyCodeResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/phone/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "phone_number": phoneNumber,
            "code": code
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhoneAuthError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 400 {
            throw PhoneAuthError.invalidCode
        }

        if httpResponse.statusCode == 410 {
            throw PhoneAuthError.codeExpired
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw PhoneAuthError.serverError(errorResponse.message ?? "Verification failed")
            }
            throw PhoneAuthError.verificationFailed
        }

        return try JSONDecoder().decode(VerifyCodeResponse.self, from: data)
    }

    /// Register new user with verified phone number
    /// - Parameters:
    ///   - phoneNumber: Verified phone number
    ///   - verificationToken: Token from successful verification
    ///   - username: Desired username
    ///   - password: Password for the account
    ///   - displayName: Optional display name
    /// - Returns: Registration response with auth tokens
    func registerWithPhone(
        phoneNumber: String,
        verificationToken: String,
        username: String,
        password: String,
        displayName: String? = nil
    ) async throws -> PhoneRegisterResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/phone/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "phone_number": phoneNumber,
            "verification_token": verificationToken,
            "username": username,
            "password": password
        ]

        if let displayName = displayName, !displayName.isEmpty {
            body["display_name"] = displayName
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhoneAuthError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 409 {
            throw PhoneAuthError.phoneAlreadyRegistered
        }

        if httpResponse.statusCode != 200 && httpResponse.statusCode != 201 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw PhoneAuthError.serverError(errorResponse.message ?? "Registration failed")
            }
            throw PhoneAuthError.registrationFailed
        }

        return try JSONDecoder().decode(PhoneRegisterResponse.self, from: data)
    }

    /// Login with phone number (for existing users)
    /// - Parameters:
    ///   - phoneNumber: Phone number in E.164 format
    ///   - verificationToken: Token from successful verification
    /// - Returns: Login response with auth tokens
    func loginWithPhone(
        phoneNumber: String,
        verificationToken: String
    ) async throws -> PhoneRegisterResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)/api/v2/auth/phone/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "phone_number": phoneNumber,
            "verification_token": verificationToken
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhoneAuthError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 404 {
            throw PhoneAuthError.phoneNotRegistered
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw PhoneAuthError.serverError(errorResponse.message ?? "Login failed")
            }
            throw PhoneAuthError.loginFailed
        }

        return try JSONDecoder().decode(PhoneRegisterResponse.self, from: data)
    }
}

// MARK: - Phone Auth Errors

enum PhoneAuthError: LocalizedError {
    case sendCodeFailed
    case invalidCode
    case codeExpired
    case verificationFailed
    case registrationFailed
    case loginFailed
    case phoneAlreadyRegistered
    case phoneNotRegistered
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
            return "Phone verification failed"
        case .registrationFailed:
            return "Registration failed"
        case .loginFailed:
            return "Login failed"
        case .phoneAlreadyRegistered:
            return "This phone number is already registered"
        case .phoneNotRegistered:
            return "No account found with this phone number"
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
