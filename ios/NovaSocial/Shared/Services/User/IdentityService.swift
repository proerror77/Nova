import Foundation

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
        }

        let request = RegisterRequest(
            username: username,
            email: email,
            password: password,
            display_name: displayName,
            invite_code: inviteCode
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
        }

        let request = LoginRequest(username: username, password: password)

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
        struct GetUserResponse: Codable {
            let user: UserProfile
        }

        let response: GetUserResponse = try await client.request(
            endpoint: APIConfig.Profile.getProfile(userId),
            method: "GET"
        )

        return response.user
    }

    /// Update user profile
    func updateUser(userId: String, updates: UserProfileUpdate) async throws -> UserProfile {
        struct UpdateUserResponse: Codable {
            let user: UserProfile
        }

        let response: UpdateUserResponse = try await client.request(
            endpoint: APIConfig.Profile.updateProfile(userId),
            method: "PUT",
            body: updates
        )

        return response.user
    }
}

// MARK: - Request/Response Models

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let user: UserProfile

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
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
