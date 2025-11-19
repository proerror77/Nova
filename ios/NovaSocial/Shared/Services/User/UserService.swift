import Foundation

// MARK: - User Service
// Handles user profile operations via UserService backend

class UserService {
    private let client = APIClient.shared

    // MARK: - User Profile

    /// Get user profile by ID
    func getUser(userId: String) async throws -> UserProfile {
        // Use IdentityService to get user data via HTTP API
        let identityService = IdentityService()
        return try await identityService.getUser(userId: userId)
    }

    /// Update user profile
    func updateProfile(
        userId: String,
        displayName: String? = nil,
        bio: String? = nil,
        avatarUrl: String? = nil,
        coverUrl: String? = nil,
        website: String? = nil,
        location: String? = nil
    ) async throws -> UserProfile {
        // Use IdentityService to update user profile via HTTP API
        let identityService = IdentityService()
        let updates = UserProfileUpdate(
            displayName: displayName,
            bio: bio,
            avatarUrl: avatarUrl,
            coverUrl: coverUrl,
            website: website,
            location: location
        )
        return try await identityService.updateUser(userId: userId, updates: updates)
    }

    // MARK: - Settings

    /// Get user settings
    func getSettings(userId: String) async throws -> UserSettings {
        // TODO: Implement gRPC call to UserService.GetSettings
        throw APIError.notFound
    }

    /// Update user settings
    func updateSettings(
        userId: String,
        notificationsEnabled: Bool? = nil,
        privateAccount: Bool? = nil,
        language: String? = nil,
        theme: String? = nil
    ) async throws {
        // TODO: Implement gRPC call to UserService.UpdateSettings
        throw APIError.notFound
    }

    // MARK: - Authentication (Future: should move to IdentityService)

    /// Logout user
    func logout() async throws {
        // TODO: This should be in IdentityService
        // For now, just clear local tokens
        // await AuthManager.shared.clearTokens()
    }

    /// Delete account
    func deleteAccount(userId: String) async throws -> Bool {
        // TODO: This should be in IdentityService
        // Implement account deletion
        throw APIError.notFound
    }
}
