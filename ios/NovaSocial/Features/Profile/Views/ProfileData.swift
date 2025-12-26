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
    var isLoadingMore = false
    var errorMessage: String?

    // MARK: - Search State
    var searchQuery: String = ""
    var isSearching = false

    // MARK: - Pagination
    private let pageSize = 20
    private var postsOffset = 0
    private var savedPostsOffset = 0
    private var likedPostsOffset = 0
    private var totalPosts = 0
    private var totalSavedPosts = 0
    private var totalLikedPosts = 0

    var hasMorePosts: Bool { posts.count < totalPosts }
    var hasMoreSavedPosts: Bool { savedPosts.count < totalSavedPosts }
    var hasMoreLikedPosts: Bool { likedPosts.count < totalLikedPosts }

    var hasMoreCurrentTabContent: Bool {
        switch selectedTab {
        case .posts: return hasMorePosts
        case .saved: return hasMoreSavedPosts
        case .liked: return hasMoreLikedPosts
        }
    }

    // MARK: - Services

    private let identityService = IdentityService()
    private let graphService = GraphService()
    private let socialService = SocialService()
    private let contentService = ContentService()
    private let mediaService = MediaService()
    private let userService = UserService.shared

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

    // MARK: - Cache Management
    private var lastLoadTime: [ContentTab: Date] = [:]
    private let cacheValidDuration: TimeInterval = 300 // 5 minutes

    private func shouldRefreshTab(_ tab: ContentTab) -> Bool {
        guard let lastLoad = lastLoadTime[tab] else { return true }
        return Date().timeIntervalSince(lastLoad) > cacheValidDuration
    }

    private func hasCachedContent(for tab: ContentTab) -> Bool {
        switch tab {
        case .posts: return !posts.isEmpty
        case .saved: return !savedPosts.isEmpty
        case .liked: return !likedPosts.isEmpty
        }
    }

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

    func loadContent(for tab: ContentTab, forceRefresh: Bool = false) async {
        guard let userId = userProfile?.id else { return }

        // Skip loading if we have valid cached content
        if !forceRefresh && hasCachedContent(for: tab) && !shouldRefreshTab(tab) {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            switch tab {
            case .posts:
                // Reset pagination for initial load
                postsOffset = 0
                let response = try await contentService.getPostsByAuthor(authorId: userId, limit: pageSize, offset: 0)
                posts = response.posts
                totalPosts = response.totalCount

            case .saved:
                savedPostsOffset = 0
                let bookmarksResponse = try await contentService.getUserBookmarks(userId: userId)
                totalSavedPosts = bookmarksResponse.totalCount
                if !bookmarksResponse.postIds.isEmpty {
                    // Only fetch first page worth of saved posts
                    let idsToFetch = Array(bookmarksResponse.postIds.prefix(pageSize))
                    let fetchedPosts = try await contentService.getPostsByIds(idsToFetch)
                    // Enrich posts with author info if missing
                    savedPosts = await enrichPostsWithAuthorInfo(fetchedPosts)
                } else {
                    savedPosts = []
                }

            case .liked:
                likedPostsOffset = 0
                let (postIds, total) = try await socialService.getUserLikedPosts(userId: userId, limit: pageSize, offset: 0)
                totalLikedPosts = total
                if !postIds.isEmpty {
                    let fetchedPosts = try await contentService.getPostsByIds(postIds)
                    // Enrich posts with author info if missing
                    likedPosts = await enrichPostsWithAuthorInfo(fetchedPosts)
                } else {
                    likedPosts = []
                }
            }

            // Update cache timestamp
            lastLoadTime[tab] = Date()
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    func loadMoreContent(for tab: ContentTab) async {
        guard let userId = userProfile?.id, !isLoadingMore else { return }

        isLoadingMore = true

        do {
            switch tab {
            case .posts:
                guard hasMorePosts else { isLoadingMore = false; return }
                let newOffset = posts.count
                let response = try await contentService.getPostsByAuthor(authorId: userId, limit: pageSize, offset: newOffset)
                posts.append(contentsOf: response.posts)
                postsOffset = newOffset

            case .saved:
                guard hasMoreSavedPosts else { isLoadingMore = false; return }
                let bookmarksResponse = try await contentService.getUserBookmarks(userId: userId)
                let newOffset = savedPosts.count
                if newOffset < bookmarksResponse.postIds.count {
                    let idsToFetch = Array(bookmarksResponse.postIds.dropFirst(newOffset).prefix(pageSize))
                    let morePosts = try await contentService.getPostsByIds(idsToFetch)
                    let enrichedPosts = await enrichPostsWithAuthorInfo(morePosts)
                    savedPosts.append(contentsOf: enrichedPosts)
                    savedPostsOffset = newOffset
                }

            case .liked:
                guard hasMoreLikedPosts else { isLoadingMore = false; return }
                let newOffset = likedPosts.count
                let (postIds, _) = try await socialService.getUserLikedPosts(userId: userId, limit: pageSize, offset: newOffset)
                if !postIds.isEmpty {
                    let morePosts = try await contentService.getPostsByIds(postIds)
                    let enrichedPosts = await enrichPostsWithAuthorInfo(morePosts)
                    likedPosts.append(contentsOf: enrichedPosts)
                    likedPostsOffset = newOffset
                }
            }
        } catch {
            handleError(error)
        }

        isLoadingMore = false
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

    // MARK: - Author Enrichment

    /// Enrich posts with author information for those missing it
    private func enrichPostsWithAuthorInfo(_ posts: [Post]) async -> [Post] {
        // Find posts that need author info
        let postsNeedingEnrichment = posts.filter { $0.needsAuthorEnrichment }
        guard !postsNeedingEnrichment.isEmpty else { return posts }

        // Get unique author IDs
        let authorIds = Array(Set(postsNeedingEnrichment.map { $0.authorId }))

        // Fetch author profiles IN PARALLEL for better performance
        var authorProfiles: [String: UserProfile] = [:]

        await withTaskGroup(of: (String, UserProfile?).self) { group in
            for authorId in authorIds {
                group.addTask {
                    do {
                        let profile = try await self.userService.getUser(userId: authorId)
                        return (authorId, profile)
                    } catch {
                        #if DEBUG
                        print("[ProfileData] Failed to fetch author \(authorId): \(error)")
                        #endif
                        return (authorId, nil)
                    }
                }
            }

            // Collect results
            for await (authorId, profile) in group {
                if let profile = profile {
                    authorProfiles[authorId] = profile
                }
            }
        }

        // Enrich posts with author info
        return posts.map { post in
            if post.needsAuthorEnrichment, let author = authorProfiles[post.authorId] {
                return post.withAuthorInfo(
                    username: author.username,
                    displayName: author.displayName,
                    avatarUrl: author.avatarUrl
                )
            }
            return post
        }
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
