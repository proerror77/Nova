import Foundation
@testable import NovaApp

/// Mock Auth Repository for unit testing
class MockAuthRepository: AuthRepository {
    // MARK: - Mock Data
    var mockAuthResult: AuthResult?
    var mockUser: User?
    var mockError: Error?

    // MARK: - Call Counters
    var signInCallCount = 0
    var signUpCallCount = 0
    var signOutCallCount = 0
    var refreshTokenCallCount = 0
    var getCurrentUserCallCount = 0
    var updateProfileCallCount = 0
    var deleteAccountCallCount = 0

    // MARK: - Recorded Calls
    var lastSignInEmail: String?
    var lastSignInPassword: String?
    var lastSignUpUsername: String?
    var lastSignUpEmail: String?
    var lastSignUpPassword: String?
    var lastUpdatedDisplayName: String?
    var lastUpdatedBio: String?

    // MARK: - Mock Responses
    override func signIn(email: String, password: String) async throws -> AuthResult {
        signInCallCount += 1
        lastSignInEmail = email
        lastSignInPassword = password

        if let error = mockError {
            throw error
        }

        if let result = mockAuthResult {
            return result
        }

        // Default mock response
        return AuthResult(
            accessToken: "mock_access_token",
            refreshToken: "mock_refresh_token",
            user: User.mock(username: email.split(separator: "@").first.map(String.init) ?? "user")
        )
    }

    override func signUp(username: String, email: String, password: String) async throws -> AuthResult {
        signUpCallCount += 1
        lastSignUpUsername = username
        lastSignUpEmail = email
        lastSignUpPassword = password

        if let error = mockError {
            throw error
        }

        if let result = mockAuthResult {
            return result
        }

        // Default mock response
        return AuthResult(
            accessToken: "mock_access_token",
            refreshToken: "mock_refresh_token",
            user: User.mock(username: username)
        )
    }

    override func signOut() async throws {
        signOutCallCount += 1

        if let error = mockError {
            throw error
        }
    }

    override func refreshToken(_ refreshToken: String) async throws -> TokenResult {
        refreshTokenCallCount += 1

        if let error = mockError {
            throw error
        }

        // Default mock response
        return TokenResult(
            accessToken: "new_access_token",
            refreshToken: "new_refresh_token"
        )
    }

    override func getCurrentUser() async throws -> User {
        getCurrentUserCallCount += 1

        if let error = mockError {
            throw error
        }

        if let user = mockUser {
            return user
        }

        // Default mock response
        return User.mock()
    }

    override func updateProfile(
        userId: String,
        displayName: String?,
        bio: String?,
        avatarData: Data?
    ) async throws -> User {
        updateProfileCallCount += 1
        lastUpdatedDisplayName = displayName
        lastUpdatedBio = bio

        if let error = mockError {
            throw error
        }

        if let user = mockUser {
            return user
        }

        // Default mock response
        return User.mock(displayName: displayName ?? "Updated User", bio: bio)
    }

    override func deleteAccount(userId: String) async throws {
        deleteAccountCallCount += 1

        if let error = mockError {
            throw error
        }
    }

    // MARK: - Reset
    func reset() {
        mockAuthResult = nil
        mockUser = nil
        mockError = nil
        signInCallCount = 0
        signUpCallCount = 0
        signOutCallCount = 0
        refreshTokenCallCount = 0
        getCurrentUserCallCount = 0
        updateProfileCallCount = 0
        deleteAccountCallCount = 0
        lastSignInEmail = nil
        lastSignInPassword = nil
        lastSignUpUsername = nil
        lastSignUpEmail = nil
        lastSignUpPassword = nil
        lastUpdatedDisplayName = nil
        lastUpdatedBio = nil
    }
}

// MARK: - Auth Models
struct AuthResult: Codable {
    let accessToken: String
    let refreshToken: String
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct TokenResult: Codable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
