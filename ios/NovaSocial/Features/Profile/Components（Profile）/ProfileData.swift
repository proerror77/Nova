import Foundation
import SwiftUI

@Observable
@MainActor
class ProfileData {
    // MARK: - Properties

    var userProfile: UserProfile?
    var posts: [Post] = []
    var savedPosts: [Post] = []
    var likedPosts: [Post] = []

    var isLoading = false
    var errorMessage: String?

    // MARK: - Services

    private let identityService = IdentityService()
    private let graphService = GraphService()
    private let socialService = SocialService()
    private let contentService = ContentService()
    private let mediaService = MediaService()

    // MARK: - Current User ID
    // TODO: Get from authentication service
    private var currentUserId: String = "current_user_id"

    // MARK: - Tab State

    enum ContentTab {
        case posts
        case saved
        case liked
    }

    var selectedTab: ContentTab = .posts

    // MARK: - Lifecycle Methods

    func loadUserProfile(userId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch user profile from IdentityService
            userProfile = try await identityService.getUser(userId: userId)

            // Load initial content based on selected tab
            await loadContent(for: selectedTab)
        } catch {
            handleError(error)
            userProfile = nil
        }

        isLoading = false
    }

    func loadContent(for tab: ContentTab) async {
        guard let userId = userProfile?.id else { return }

        isLoading = true
        errorMessage = nil

        do {
            switch tab {
            case .posts:
                let response = try await contentService.getPostsByAuthor(authorId: userId)
                posts = response.posts

            case .saved:
                _ = try await contentService.getUserBookmarks(userId: userId)
                // API returns postIds, need to fetch actual posts if needed
                // For now, we leave savedPosts empty if we only have IDs
                savedPosts = []
                // TODO: Fetch full post data using postIds if available

            case .liked:
                // TODO: Need to fetch liked posts
                // SocialService provides user IDs who liked a post, not posts liked by a user
                // This may need a different endpoint or approach
                likedPosts = []
            }
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    // MARK: - User Actions

    func uploadAvatar(image: UIImage) async {
        guard let userId = userProfile?.id,
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Upload image to MediaService
            let avatarUrl = try await mediaService.uploadImage(image: imageData, userId: userId)

            // Update profile with new avatar URL using IdentityService
            let updates = UserProfileUpdate(
                displayName: nil,
                bio: nil,
                avatarUrl: avatarUrl,
                coverUrl: nil,
                website: nil,
                location: nil
            )
            userProfile = try await identityService.updateUser(userId: userId, updates: updates)
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    func followUser() async {
        guard let userId = userProfile?.id else { return }

        do {
            try await graphService.followUser(followerId: currentUserId, followeeId: userId)
            // TODO: Reload profile to get updated follower count
            // Need to fetch updated follower count from somewhere
        } catch {
            handleError(error)
        }
    }

    func unfollowUser() async {
        guard let userId = userProfile?.id else { return }

        do {
            try await graphService.unfollowUser(followerId: currentUserId, followeeId: userId)
            // TODO: Reload profile to get updated follower count
            // Need to fetch updated follower count from somewhere
        } catch {
            handleError(error)
        }
    }

    func likePost(postId: String) async {
        do {
            try await socialService.createLike(postId: postId, userId: currentUserId)
            // Reload content to reflect the change
            await loadContent(for: selectedTab)
        } catch {
            handleError(error)
        }
    }

    func unlikePost(postId: String) async {
        do {
            try await socialService.deleteLike(postId: postId, userId: currentUserId)
            // Reload content to reflect the change
            await loadContent(for: selectedTab)
        } catch {
            handleError(error)
        }
    }

    func shareProfile() {
        guard let userId = userProfile?.id else { return }
        // Generate share URL
        let shareUrl = "https://nova.social/user/\(userId)"

        // TODO: Implement native share sheet
        print("Share URL: \(shareUrl)")
    }

    func searchInProfile(query: String) async {
        // TODO: Implement profile content search
        print("Searching for: \(query)")
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        if let apiError = error as? APIError {
            errorMessage = apiError.userMessage
        } else {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Computed Properties

    var currentTabPosts: [Post] {
        switch selectedTab {
        case .posts:
            return posts
        case .saved:
            return savedPosts
        case .liked:
            return likedPosts
        }
    }

    var hasContent: Bool {
        !currentTabPosts.isEmpty
    }

    // MARK: - Mock Data for Preview
    #if DEBUG
    static func preview() -> ProfileData {
        let data = ProfileData()
        data.userProfile = UserProfile(
            id: "mock-user-id",
            username: "bruce_li",
            email: "bruce@example.com",
            displayName: "Bruce Li",
            bio: "iOS Developer | Tech Enthusiast",
            avatarUrl: nil,
            coverUrl: nil,
            website: "https://bruce.dev",
            location: "China",
            isVerified: true,
            isPrivate: false,
            isBanned: false,
            followerCount: 3021,
            followingCount: 1500,
            postCount: 245,
            createdAt: Int64(Date().timeIntervalSince1970 - 365*24*60*60),
            updatedAt: Int64(Date().timeIntervalSince1970),
            deletedAt: nil,
            firstName: "Bruce",
            lastName: "Li",
            dateOfBirth: "1990-01-15",
            gender: .male
        )
        return data
    }
    #endif
}
