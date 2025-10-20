import Foundation
@testable import NovaApp

/// Mock Profile Repository for unit testing
class MockProfileRepository: ProfileRepository {
    // MARK: - Mock Data
    var mockProfileResponse: ProfileResponse?
    var mockUpdatedUser: User?
    var mockError: Error?
    var delayDuration: TimeInterval = 0

    // MARK: - Call Tracking
    var fetchProfileCallCount = 0
    var followUserCallCount = 0
    var unfollowUserCallCount = 0
    var updateProfileCallCount = 0

    // MARK: - Recorded Parameters
    var lastFetchedUserId: String?
    var lastFollowedUserId: String?
    var lastUnfollowedUserId: String?
    var lastUpdateUserId: String?
    var lastDisplayName: String?
    var lastBio: String?
    var lastAvatarData: Data?

    // MARK: - Mock Responses

    override func fetchProfile(userId: String) async throws -> ProfileResponse {
        fetchProfileCallCount += 1
        lastFetchedUserId = userId

        if delayDuration > 0 {
            try await Task.sleep(nanoseconds: UInt64(delayDuration * 1_000_000_000))
        }

        if let error = mockError {
            throw error
        }

        if let response = mockProfileResponse {
            return response
        }

        // Default mock response
        return ProfileResponse(
            user: User.mock(id: userId),
            posts: [],
            isFollowing: false
        )
    }

    override func followUser(userId: String) async throws {
        followUserCallCount += 1
        lastFollowedUserId = userId

        if delayDuration > 0 {
            try await Task.sleep(nanoseconds: UInt64(delayDuration * 1_000_000_000))
        }

        if let error = mockError {
            throw error
        }
    }

    override func unfollowUser(userId: String) async throws {
        unfollowUserCallCount += 1
        lastUnfollowedUserId = userId

        if delayDuration > 0 {
            try await Task.sleep(nanoseconds: UInt64(delayDuration * 1_000_000_000))
        }

        if let error = mockError {
            throw error
        }
    }

    override func updateProfile(
        userId: String,
        displayName: String,
        bio: String,
        avatarData: Data?
    ) async throws -> User {
        updateProfileCallCount += 1
        lastUpdateUserId = userId
        lastDisplayName = displayName
        lastBio = bio
        lastAvatarData = avatarData

        if delayDuration > 0 {
            try await Task.sleep(nanoseconds: UInt64(delayDuration * 1_000_000_000))
        }

        if let error = mockError {
            throw error
        }

        if let user = mockUpdatedUser {
            return user
        }

        // Default mock response
        return User.mock(
            id: userId,
            displayName: displayName,
            bio: bio
        )
    }

    // MARK: - Reset

    func reset() {
        mockProfileResponse = nil
        mockUpdatedUser = nil
        mockError = nil
        delayDuration = 0

        fetchProfileCallCount = 0
        followUserCallCount = 0
        unfollowUserCallCount = 0
        updateProfileCallCount = 0

        lastFetchedUserId = nil
        lastFollowedUserId = nil
        lastUnfollowedUserId = nil
        lastUpdateUserId = nil
        lastDisplayName = nil
        lastBio = nil
        lastAvatarData = nil
    }
}
