import Foundation

/// Handles social interactions (like, bookmark, share) for feed posts
/// Extracted from FeedViewModel to follow Single Responsibility Principle
@MainActor
final class FeedSocialActionsHandler {
    // MARK: - Dependencies

    private let socialService: SocialService
    private let authManager: AuthenticationManager

    // MARK: - State

    /// Track ongoing like operations to prevent concurrent calls for the same post
    private var ongoingLikeOperations: Set<String> = []

    /// Track ongoing bookmark operations to prevent concurrent calls for the same post
    private var ongoingBookmarkOperations: Set<String> = []

    // MARK: - Cooldown State (Instagram-style throttle)

    /// Cooldown period in seconds - ignore clicks during this time
    private let cooldownDuration: TimeInterval = 0.5

    /// Timestamp of last like action per post (for cooldown)
    private var lastLikeTime: [String: Date] = [:]

    /// Timestamp of last bookmark action per post (for cooldown)
    private var lastBookmarkTime: [String: Date] = [:]

    // MARK: - Callbacks
    
    /// Callback to update post in the feed
    var onPostUpdate: ((String, (FeedPost) -> FeedPost) -> Void)?
    
    /// Callback to show toast error
    var onError: ((String) -> Void)?
    
    // MARK: - Computed Properties
    
    private var currentUserId: String? {
        KeychainService.shared.get(.userId)
    }
    
    private var isAuthenticated: Bool {
        authManager.isAuthenticated && !authManager.isGuestMode
    }
    
    // MARK: - Init
    
    init(
        socialService: SocialService = SocialService(),
        authManager: AuthenticationManager = AuthenticationManager.shared
    ) {
        self.socialService = socialService
        self.authManager = authManager
    }
    
    // MARK: - Like Actions

    /// Toggle like on a post with cooldown (Instagram-style)
    /// - First click: immediately updates UI and sends API request
    /// - Subsequent clicks within cooldown period: ignored
    func toggleLike(postId: String, currentPost: FeedPost) async -> Bool {
        guard currentUserId != nil else {
            #if DEBUG
            print("[FeedSocialActions] toggleLike early return - userId is nil")
            #endif
            return false
        }

        // Check cooldown - ignore clicks within cooldown period
        if let lastTime = lastLikeTime[postId],
           Date().timeIntervalSince(lastTime) < cooldownDuration {
            #if DEBUG
            print("[FeedSocialActions] toggleLike ignored - within cooldown for postId: \(postId)")
            #endif
            return false
        }

        // Also check if operation already in progress
        guard !ongoingLikeOperations.contains(postId) else {
            #if DEBUG
            print("[FeedSocialActions] toggleLike ignored - operation in progress for postId: \(postId)")
            #endif
            return false
        }

        // Update cooldown timestamp
        lastLikeTime[postId] = Date()

        let wasLiked = currentPost.isLiked
        let newLikeCount = wasLiked ? max(0, currentPost.likeCount - 1) : currentPost.likeCount + 1

        // Optimistic update - immediate UI feedback
        onPostUpdate?(postId) { post in
            post.copying(likeCount: newLikeCount, isLiked: !wasLiked)
        }

        // Perform API call
        await performLikeOperation(
            postId: postId,
            originalPost: currentPost,
            targetLikedState: !wasLiked
        )

        return true
    }

    /// Perform the actual like/unlike API call
    private func performLikeOperation(
        postId: String,
        originalPost: FeedPost,
        targetLikedState: Bool
    ) async {
        guard let userId = currentUserId else { return }

        ongoingLikeOperations.insert(postId)
        defer { ongoingLikeOperations.remove(postId) }

        do {
            let response: SocialService.LikeResponse
            if targetLikedState {
                response = try await socialService.createLike(postId: postId, userId: userId)
            } else {
                response = try await socialService.deleteLike(postId: postId, userId: userId)
            }

            // Update UI with server's accurate count
            onPostUpdate?(postId) { post in
                post.copying(likeCount: Int(response.likeCount), isLiked: targetLikedState)
            }

            await FeedCacheService.shared.invalidateCache()

            #if DEBUG
            print("[FeedSocialActions] Like operation completed for postId: \(postId), isLiked: \(targetLikedState), count: \(response.likeCount)")
            #endif
        } catch let error as APIError {
            // Revert on failure
            onPostUpdate?(postId) { _ in originalPost }
            handleError(error, action: "like")
        } catch {
            // Revert on failure
            onPostUpdate?(postId) { _ in originalPost }
            onError?("Failed to like post. Please try again.")
            #if DEBUG
            print("[FeedSocialActions] Toggle like error: \(error)")
            #endif
        }
    }
    
    // MARK: - Bookmark Actions

    /// Toggle bookmark on a post with cooldown (Instagram-style)
    func toggleBookmark(postId: String, currentPost: FeedPost) async -> Bool {
        guard currentUserId != nil else {
            #if DEBUG
            print("[FeedSocialActions] toggleBookmark early return - userId is nil")
            #endif
            return false
        }

        // Check cooldown
        if let lastTime = lastBookmarkTime[postId],
           Date().timeIntervalSince(lastTime) < cooldownDuration {
            #if DEBUG
            print("[FeedSocialActions] toggleBookmark ignored - within cooldown for postId: \(postId)")
            #endif
            return false
        }

        guard !ongoingBookmarkOperations.contains(postId) else {
            #if DEBUG
            print("[FeedSocialActions] toggleBookmark ignored - operation in progress for postId: \(postId)")
            #endif
            return false
        }

        // Update cooldown timestamp
        lastBookmarkTime[postId] = Date()

        let wasBookmarked = currentPost.isBookmarked
        let newBookmarkCount = wasBookmarked ? max(0, currentPost.bookmarkCount - 1) : currentPost.bookmarkCount + 1

        // Optimistic update
        onPostUpdate?(postId) { post in
            post.copying(bookmarkCount: newBookmarkCount, isBookmarked: !wasBookmarked)
        }

        // Perform API call
        await performBookmarkOperation(
            postId: postId,
            originalPost: currentPost,
            targetBookmarkedState: !wasBookmarked
        )

        return true
    }

    /// Perform the actual bookmark/unbookmark API call
    private func performBookmarkOperation(
        postId: String,
        originalPost: FeedPost,
        targetBookmarkedState: Bool
    ) async {
        guard let userId = currentUserId else { return }

        ongoingBookmarkOperations.insert(postId)
        defer { ongoingBookmarkOperations.remove(postId) }

        do {
            if targetBookmarkedState {
                try await socialService.createBookmark(postId: postId, userId: userId)
            } else {
                try await socialService.deleteBookmark(postId: postId)
            }

            await FeedCacheService.shared.invalidateCache()

            #if DEBUG
            print("[FeedSocialActions] Bookmark operation completed for postId: \(postId), isBookmarked: \(targetBookmarkedState)")
            #endif
        } catch let error as APIError {
            switch error {
            case .notFound, .serverError, .serviceUnavailable:
                // Backend bookmark API not deployed yet - keep local state
                #if DEBUG
                print("[FeedSocialActions] Bookmark API not available (\(error)), using local state only")
                #endif
            default:
                // Revert on failure
                onPostUpdate?(postId) { _ in originalPost }
                handleError(error, action: "bookmark")
            }
        } catch {
            onPostUpdate?(postId) { _ in originalPost }
            onError?("Failed to bookmark post. Please try again.")
            #if DEBUG
            print("[FeedSocialActions] Toggle bookmark error: \(error)")
            #endif
        }
    }
    
    // MARK: - Share Actions
    
    /// Share a post - records share to backend
    /// - Parameters:
    ///   - postId: The post ID to share
    ///   - currentPost: The current post state
    /// - Returns: The post to share, or nil if user not authenticated
    func sharePost(postId: String, currentPost: FeedPost) async -> FeedPost? {
        guard let userId = currentUserId else { return nil }
        
        // Record share to backend (don't block on this)
        Task {
            do {
                try await socialService.createShare(postId: postId, userId: userId)
                // Update share count on success
                await MainActor.run { [weak self] in
                    self?.onPostUpdate?(postId) { post in
                        post.copying(shareCount: post.shareCount + 1)
                    }
                }
            } catch {
                #if DEBUG
                print("[FeedSocialActions] Share post error: \(error)")
                #endif
            }
        }
        
        return currentPost
    }
    
    /// Increment comment count for a post (called when a comment is successfully added)
    func incrementCommentCount(postId: String) {
        onPostUpdate?(postId) { post in
            post.copying(commentCount: post.commentCount + 1)
        }
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: APIError, action: String) {
        switch error {
        case .unauthorized:
            onError?("Please try again.")
            #if DEBUG
            print("[FeedSocialActions] Toggle \(action) error: Unauthorized, will retry on next action")
            #endif
        case .noConnection:
            onError?("No internet connection. Please try again.")
        case .serviceUnavailable:
            onError?("Service temporarily unavailable. Please try again later.")
            #if DEBUG
            print("[FeedSocialActions] Toggle \(action) error: Service unavailable (503)")
            #endif
        default:
            onError?("Failed to \(action) post. Please try again.")
            #if DEBUG
            print("[FeedSocialActions] Toggle \(action) error: \(error)")
            #endif
        }
    }
}
