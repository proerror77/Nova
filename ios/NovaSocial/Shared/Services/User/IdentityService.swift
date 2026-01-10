import Foundation
import UIKit

// MARK: - Identity Service
// Handles authentication and user identity operations via identity-service backend

class IdentityService {
    private let client = APIClient.shared

    // MARK: - Authentication

    /// Register a new user
    func register(username: String, email: String, password: String, displayName: String, inviteCode: String = "NOVATEST") async throws -> AuthResponse {
        struct RegisterRequest: Codable {
            let username: String
            let email: String
            let password: String
            let display_name: String
            let invite_code: String
            // Device information for session tracking
            let device_id: String?
            let device_name: String?
            let device_type: String?
            let os_version: String?
            let user_agent: String?
        }

        // Get device information (must access on main actor)
        let (deviceId, deviceName, deviceType, osVersion, deviceModel) = await MainActor.run {
            let device = UIDevice.current
            let id = device.identifierForVendor?.uuidString
            let name = device.name
            let systemName = device.systemName
            let systemVersion = device.systemVersion
            let model = device.model

            let type: String
            switch device.userInterfaceIdiom {
            case .phone:
                type = "iOS"
            case .pad:
                type = "iOS"
            case .mac:
                type = "macOS"
            default:
                type = "iOS"
            }

            return (id, name, type, "\(systemName) \(systemVersion)", model)
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let request = RegisterRequest(
            username: username,
            email: email,
            password: password,
            display_name: displayName,
            invite_code: inviteCode,
            device_id: deviceId,
            device_name: deviceName,
            device_type: deviceType,
            os_version: osVersion,
            user_agent: "NovaSocial/\(appVersion) (\(deviceModel))"
        )

        let response: AuthResponse = try await client.request(
            endpoint: APIConfig.Auth.register,
            method: "POST",
            body: request
        )

        // Save token for subsequent requests
        client.setAuthToken(response.accessToken)

        return response
    }

    /// Login user
    func login(username: String, password: String) async throws -> AuthResponse {
        struct LoginRequest: Codable {
            let username: String
            let password: String
            // Device information for session tracking
            let device_id: String?
            let device_name: String?
            let device_type: String?
            let os_version: String?
            let user_agent: String?
        }

        // Get device information (must access on main actor)
        let (deviceId, deviceName, deviceType, osVersion, deviceModel) = await MainActor.run {
            let device = UIDevice.current
            let id = device.identifierForVendor?.uuidString
            let name = device.name
            let systemName = device.systemName
            let systemVersion = device.systemVersion
            let model = device.model

            // Determine device type based on userInterfaceIdiom
            let type: String
            switch device.userInterfaceIdiom {
            case .phone:
                type = "iOS"
            case .pad:
                type = "iOS" // iPad is still iOS
            case .mac:
                type = "macOS"
            default:
                type = "iOS"
            }

            return (id, name, type, "\(systemName) \(systemVersion)", model)
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let request = LoginRequest(
            username: username,
            password: password,
            device_id: deviceId,
            device_name: deviceName,
            device_type: deviceType,
            os_version: osVersion,
            user_agent: "NovaSocial/\(appVersion) (\(deviceModel))"
        )

        let response: AuthResponse = try await client.request(
            endpoint: APIConfig.Auth.login,
            method: "POST",
            body: request
        )

        // Save token for subsequent requests
        client.setAuthToken(response.accessToken)

        return response
    }

    /// Refresh access token
    func refreshToken(refreshToken: String) async throws -> AuthResponse {
        struct RefreshRequest: Codable {
            let refresh_token: String
        }

        let request = RefreshRequest(refresh_token: refreshToken)

        let response: AuthResponse = try await client.request(
            endpoint: APIConfig.Auth.refresh,
            method: "POST",
            body: request
        )

        // Update token
        client.setAuthToken(response.accessToken)

        return response
    }

    /// Logout user
    func logout() async throws {
        struct LogoutRequest: Codable {
            // Empty request body or include user_id if needed
        }

        _ = try await client.request(
            endpoint: APIConfig.Auth.logout,
            method: "POST",
            body: LogoutRequest()
        ) as EmptyResponse

        // Clear local token
        client.setAuthToken("")
    }

    // MARK: - User Profile

    /// Get user profile by ID
    func getUser(userId: String) async throws -> UserProfile {
        let response: UserEnvelope = try await client.request(
            endpoint: APIConfig.Profile.getProfile(userId),
            method: "GET"
        )
        return response.user
    }

    /// Update user profile
    func updateUser(userId: String, updates: UserProfileUpdate) async throws -> UserProfile {
        let response: UserEnvelope = try await client.request(
            endpoint: APIConfig.Profile.updateProfile(userId),
            method: "PUT",
            body: updates
        )
        return response.user
    }

    // MARK: - Password Management

    /// Change password (requires current password verification)
    func changePassword(userId: String, oldPassword: String, newPassword: String) async throws {
        struct Request: Codable {
            let userId: String
            let oldPassword: String
            let newPassword: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case oldPassword = "old_password"
                case newPassword = "new_password"
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(userId: userId, oldPassword: oldPassword, newPassword: newPassword)

        let _: Response = try await client.request(
            endpoint: APIConfig.Auth.changePassword,
            method: "POST",
            body: request
        )
    }

    /// Request password reset (sends reset link to email)
    func requestPasswordReset(email: String) async throws {
        struct Request: Codable {
            let email: String
        }

        struct Response: Codable {
            let success: Bool
            let message: String?
        }

        let request = Request(email: email)

        let _: Response = try await client.request(
            endpoint: APIConfig.Auth.requestPasswordReset,
            method: "POST",
            body: request
        )
    }

    /// Reset password using reset token
    func resetPassword(resetToken: String, newPassword: String) async throws {
        struct Request: Codable {
            let resetToken: String
            let newPassword: String

            enum CodingKeys: String, CodingKey {
                case resetToken = "reset_token"
                case newPassword = "new_password"
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(resetToken: resetToken, newPassword: newPassword)

        let _: Response = try await client.request(
            endpoint: APIConfig.Auth.resetPassword,
            method: "POST",
            body: request
        )
    }

    // MARK: - Token Management

    /// Verify if a token is valid
    func verifyToken(token: String) async throws -> TokenVerificationResult {
        struct Request: Codable {
            let accessToken: String

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
            }
        }

        let request = Request(accessToken: token)

        return try await client.request(
            endpoint: APIConfig.Auth.verifyToken,
            method: "POST",
            body: request
        )
    }

    /// Revoke a specific token
    func revokeToken(token: String) async throws {
        struct Request: Codable {
            let accessToken: String

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(accessToken: token)

        let _: Response = try await client.request(
            endpoint: APIConfig.Auth.revokeToken,
            method: "POST",
            body: request
        )

        // Clear local token if revoking current token
        client.setAuthToken("")
    }

    /// Revoke all tokens for a user (logout from all devices)
    func revokeAllTokens(userId: String) async throws {
        struct Request: Codable {
            let userId: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(userId: userId)

        let _: Response = try await client.request(
            endpoint: APIConfig.Auth.revokeAllTokens,
            method: "POST",
            body: request
        )

        // Clear local token
        client.setAuthToken("")
    }

    // MARK: - Session Management

    /// Get list of active sessions for a user
    func getActiveSessions(userId: String) async throws -> [UserSession] {
        struct Response: Codable {
            let sessions: [UserSession]
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Auth.sessions(userId)
        )

        return response.sessions
    }

    /// Verify password (check if password is correct)
    func verifyPassword(userId: String, password: String) async throws -> Bool {
        struct Request: Codable {
            let userId: String
            let password: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case password
            }
        }

        struct Response: Codable {
            let valid: Bool
        }

        let request = Request(userId: userId, password: password)

        let response: Response = try await client.request(
            endpoint: APIConfig.Auth.verifyPassword,
            method: "POST",
            body: request
        )

        return response.valid
    }
}

// MARK: - Flexible user envelope

/// Some endpoints return `{ \"user\": { ... } }`, others return the user object directly.
private struct UserEnvelope: Codable {
    let user: UserProfile

    enum CodingKeys: String, CodingKey {
        case user
    }

    init(from decoder: Decoder) throws {
        // Try keyed container first: { "user": { ... } }
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let wrapped = try? container.decode(UserProfile.self, forKey: .user) {
            self.user = wrapped
            return
        }
        // Fallback: top-level user object
        let single = try decoder.singleValueContainer()
        self.user = try single.decode(UserProfile.self)
    }
}

// MARK: - Additional Models

/// Token verification result
struct TokenVerificationResult: Codable {
    let valid: Bool
    let userId: String?
    let email: String?
    let username: String?
    let roles: [String]?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case valid
        case userId = "user_id"
        case email
        case username
        case roles
        case expiresAt = "expires_at"
    }
}

/// User session information
struct UserSession: Codable, Identifiable {
    let id: String  // session_id
    let deviceId: String
    let userAgent: String?
    let ipAddress: String?
    let createdAt: Date
    let lastActiveAt: Date
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "session_id"
        case deviceId = "device_id"
        case userAgent = "user_agent"
        case ipAddress = "ip_address"
        case createdAt = "created_at"
        case lastActiveAt = "last_active_at"
        case expiresAt = "expires_at"
    }
}

// MARK: - Request/Response Models

struct AuthResponse: Codable {
    let token: String
    let refreshToken: String?
    let user: UserProfile

    enum CodingKeys: String, CodingKey {
        case token
        case refreshToken = "refresh_token"
        case user
    }

    // Compatibility accessor for code expecting accessToken
    var accessToken: String { token }
}

struct UserProfileUpdate: Codable {
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
    let coverUrl: String?
    let website: String?
    let location: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case bio
        case avatarUrl = "avatar_url"
        case coverUrl = "cover_url"
        case website
        case location
    }
}

struct EmptyResponse: Codable {
    // Used for endpoints that return empty responses
}
