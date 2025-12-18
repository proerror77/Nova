import Foundation

// MARK: - User Service
// Handles user profile and settings operations via graphql-gateway/user-service backend

class UserService {
    static let shared = UserService()
    private let client = APIClient.shared

    // MARK: - Cache Configuration
    
    /// Cache entry with timestamp for TTL validation
    private struct CacheEntry {
        let profile: UserProfile
        let timestamp: Date
    }
    
    /// Cache TTL: 5 minutes
    private let cacheTTL: TimeInterval = 300
    
    /// In-memory cache for user profiles by ID
    private var profileCacheById: [String: CacheEntry] = [:]
    
    /// In-memory cache for user profiles by username
    private var profileCacheByUsername: [String: CacheEntry] = [:]
    
    /// Serial queue for thread-safe cache access
    private let cacheQueue = DispatchQueue(label: "com.novasocial.userservice.cache")

    private init() {}

    // MARK: - Cache Management
    
    /// Check if a cache entry is still valid
    private func isValidCacheEntry(_ entry: CacheEntry) -> Bool {
        return Date().timeIntervalSince(entry.timestamp) < cacheTTL
    }
    
    /// Invalidate cache for a specific user (call after profile update)
    func invalidateCache(userId: String? = nil, username: String? = nil) {
        cacheQueue.sync {
            if let userId = userId {
                profileCacheById.removeValue(forKey: userId)
            }
            if let username = username {
                profileCacheByUsername.removeValue(forKey: username.lowercased())
            }
        }
    }
    
    /// Clear all cached profiles
    func clearCache() {
        cacheQueue.sync {
            profileCacheById.removeAll()
            profileCacheByUsername.removeAll()
        }
    }
    
    /// Store profile in cache (both by ID and username)
    private func cacheProfile(_ profile: UserProfile) {
        let entry = CacheEntry(profile: profile, timestamp: Date())
        cacheQueue.sync {
            profileCacheById[profile.id] = entry
            // username is non-optional String, cache it directly
            profileCacheByUsername[profile.username.lowercased()] = entry
        }
    }

    // MARK: - User Profile

    /// Get user profile by ID (with caching)
    func getUser(userId: String) async throws -> UserProfile {
        // Check cache first
        if let cached = cacheQueue.sync(execute: { profileCacheById[userId] }),
           isValidCacheEntry(cached) {
            return cached.profile
        }
        
        struct GetUserResponse: Codable {
            let user: UserProfile
        }

        let response: GetUserResponse = try await client.request(
            endpoint: APIConfig.Profile.getProfile(userId),
            method: "GET"
        )

        // Cache the result
        cacheProfile(response.user)
        
        return response.user
    }

    /// Get user profile by username (with caching)
    func getUserByUsername(_ username: String) async throws -> UserProfile {
        let lowercasedUsername = username.lowercased()
        
        // Check cache first
        if let cached = cacheQueue.sync(execute: { profileCacheByUsername[lowercasedUsername] }),
           isValidCacheEntry(cached) {
            return cached.profile
        }
        
        struct GetUserResponse: Codable {
            let user: UserProfile
        }

        let response: GetUserResponse = try await client.request(
            endpoint: "/api/v2/users/username/\(username)",
            method: "GET"
        )

        // Cache the result
        cacheProfile(response.user)
        
        return response.user
    }

    /// Update user profile
    func updateProfile(
        userId: String,
        displayName: String? = nil,
        bio: String? = nil,
        avatarUrl: String? = nil,
        coverUrl: String? = nil,
        website: String? = nil,
        location: String? = nil,
        isPrivate: Bool? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        dateOfBirth: String? = nil,
        gender: Gender? = nil
    ) async throws -> UserProfile {
        struct UpdateProfileResponse: Codable {
            let user: UserProfile
        }

        let request = UpdateUserProfileRequest(
            userId: userId,
            displayName: displayName,
            bio: bio,
            avatarUrl: avatarUrl,
            coverUrl: coverUrl,
            website: website,
            location: location,
            isPrivate: isPrivate,
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: dateOfBirth,
            gender: gender?.rawValue
        )

        let response: UpdateProfileResponse = try await client.request(
            endpoint: APIConfig.Profile.updateProfile(userId),
            method: "PUT",
            body: request
        )

        // Update cache with new profile data
        cacheProfile(response.user)

        return response.user
    }

    // MARK: - Settings

    /// Get user settings
    func getSettings(userId: String) async throws -> UserSettings {
        struct GetSettingsResponse: Codable {
            let settings: UserSettings
        }

        let response: GetSettingsResponse = try await client.request(
            endpoint: APIConfig.Settings.getSettings(userId),
            method: "GET"
        )

        return response.settings
    }

    /// Update user settings
    /// NOTE: Uses identity-service as the SINGLE SOURCE OF TRUTH
    /// All settings including dm_permission are managed by identity-service
    func updateSettings(
        userId: String,
        emailNotifications: Bool? = nil,
        pushNotifications: Bool? = nil,
        marketingEmails: Bool? = nil,
        timezone: String? = nil,
        language: String? = nil,
        darkMode: Bool? = nil,
        privacyLevel: PrivacyLevel? = nil,
        allowMessages: Bool? = nil,
        showOnlineStatus: Bool? = nil,
        dmPermission: DmPermission? = nil
    ) async throws -> UserSettings {
        struct UpdateSettingsResponse: Codable {
            let settings: UserSettings
        }

        let request = UpdateSettingsRequest(
            userId: userId,
            emailNotifications: emailNotifications,
            pushNotifications: pushNotifications,
            marketingEmails: marketingEmails,
            timezone: timezone,
            language: language,
            darkMode: darkMode,
            privacyLevel: privacyLevel?.rawValue,
            allowMessages: allowMessages,
            showOnlineStatus: showOnlineStatus,
            dmPermission: dmPermission?.rawValue
        )

        let response: UpdateSettingsResponse = try await client.request(
            endpoint: APIConfig.Settings.updateSettings(userId),
            method: "PUT",
            body: request
        )

        return response.settings
    }

    /// Convenience method to update DM permission only
    /// - Parameters:
    ///   - userId: User ID
    ///   - permission: DM permission setting
    /// - Returns: Updated user settings
    func updateDmPermission(userId: String, permission: DmPermission) async throws -> UserSettings {
        return try await updateSettings(userId: userId, dmPermission: permission)
    }

    /// Convenience method to update dark mode only
    func updateDarkMode(userId: String, enabled: Bool) async throws -> UserSettings {
        return try await updateSettings(userId: userId, darkMode: enabled)
    }

    // MARK: - Search Users

    /// Search users by query
    func searchUsers(query: String, limit: Int = 20, offset: Int = 0) async throws -> [UserProfile] {
        struct SearchUsersResponse: Codable {
            let users: [UserProfile]
            let totalCount: Int?
            let hasMore: Bool?

            enum CodingKeys: String, CodingKey {
                case users
                case totalCount = "total_count"
                case hasMore = "has_more"
            }
        }

        let response: SearchUsersResponse = try await client.request(
            endpoint: "\(APIConfig.Search.users)?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&limit=\(limit)&offset=\(offset)",
            method: "GET"
        )

        // Cache all returned profiles
        for profile in response.users {
            cacheProfile(profile)
        }

        return response.users
    }

    // MARK: - Account Deletion

    /// Request account deletion
    func deleteAccount(userId: String, reason: String? = nil) async throws {
        struct DeleteAccountRequest: Codable {
            let userId: String
            let reason: String?

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case reason
            }
        }

        let request = DeleteAccountRequest(userId: userId, reason: reason)

        _ = try await client.request(
            endpoint: "/api/v2/users/\(userId)",
            method: "DELETE",
            body: request
        ) as EmptyResponse
        
        // Clear cache for deleted user
        invalidateCache(userId: userId)
    }
}
