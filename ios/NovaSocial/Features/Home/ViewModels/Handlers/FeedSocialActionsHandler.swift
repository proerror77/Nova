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
    
    /// Toggle like on a post
    /// - Parameters:
    ///   - postId: The post ID to like/unlike
    ///   - currentPost: The current post state
    /// - Returns: Whether the operation was initiated (false if already in progress)
    func toggleLike(postId: String, currentPost: FeedPost) async -> Bool {
        // Prevent concurrent like operations for the same post
        guard !ongoingLikeOperations.contains(postId) else {
            #if DEBUG
            print("[FeedSocialActions] toggleLike skipped - operation already in progress for postId: \(postId)")
            #endif
            return false
        }
        
        guard let userId = currentUserId else {
            #if DEBUG
            print("[FeedSocialActions] toggleLike early return - userId is nil")
            #endif
            return false
        }
        
        ongoingLikeOperations.insert(postId)
        defer { ongoingLikeOperations.remove(postId) }
        
        let wasLiked = currentPost.isLiked

        // Optimistic update - immediate UI feedback
        onPostUpdate?(postId) { post in
            post.copying(
                likeCount: wasLiked ? post.likeCount - 1 : post.likeCount + 1,
                isLiked: !wasLiked
            )
        }

        do {
            let response: SocialService.LikeResponse
            if wasLiked {
                response = try await socialService.deleteLike(postId: postId, userId: userId)
            } else {
                response = try await socialService.createLike(postId: postId, userId: userId)
            }

            // Reconcile with server's accurate count
            // This ensures UI shows the correct count from PostgreSQL (source of truth)
            onPostUpdate?(postId) { post in
                post.copying(
                    likeCount: Int(response.likeCount),
                    isLiked: !wasLiked
                )
            }

            // Invalidate feed cache on successful like/unlike to ensure
            // fresh data is fetched when user navigates back to feed
            await FeedCacheService.shared.invalidateCache()

            return true
        } catch let error as APIError {
            // Revert on failure
            onPostUpdate?(postId) { _ in currentPost }
            handleError(error, action: "like")
            return false
        } catch {
            // Revert on failure
            onPostUpdate?(postId) { _ in currentPost }
            onError?("Failed to like post. Please try again.")
            #if DEBUG
            print("[FeedSocialActions] Toggle like error: \(error)")
            #endif
            return false
        }
    }
    
    // MARK: - Bookmark Actions
    
    /// Toggle bookmark on a post
    /// - Parameters:
    ///   - postId: The post ID to bookmark/unbookmark
    ///   - currentPost: The current post state
    /// - Returns: Whether the operation was initiated (false if already in progress)
    func toggleBookmark(postId: String, currentPost: FeedPost) async -> Bool {
        // Prevent concurrent bookmark operations for the same post
        guard !ongoingBookmarkOperations.contains(postId) else {
            #if DEBUG
            print("[FeedSocialActions] toggleBookmark skipped - operation already in progress for postId: \(postId)")
            #endif
            return false
        }
        
        guard let userId = currentUserId else {
            #if DEBUG
            print("[FeedSocialActions] toggleBookmark early return - userId is nil")
            #endif
            return false
        }
        
        ongoingBookmarkOperations.insert(postId)
        defer { ongoingBookmarkOperations.remove(postId) }
        
        let wasBookmarked = currentPost.isBookmarked
        
        // Optimistic update - update both isBookmarked and bookmarkCount
        onPostUpdate?(postId) { post in
            post.copying(
                bookmarkCount: wasBookmarked ? post.bookmarkCount - 1 : post.bookmarkCount + 1,
                isBookmarked: !wasBookmarked
            )
        }
        
        do {
            if wasBookmarked {
                try await socialService.deleteBookmark(postId: postId)
            } else {
                try await socialService.createBookmark(postId: postId, userId: userId)
            }

            // Invalidate feed cache on successful bookmark/unbookmark
            await FeedCacheService.shared.invalidateCache()

            return true
        } catch let error as APIError {
            // Handle specific error cases - some errors should keep local state
            switch error {
            case .unauthorized:
                // Revert on auth error
                onPostUpdate?(postId) { _ in currentPost }
                onError?("Please try again.")
                #if DEBUG
                print("[FeedSocialActions] Toggle bookmark error: Unauthorized")
                #endif
            case .noConnection:
                // Revert on connection error
                onPostUpdate?(postId) { _ in currentPost }
                onError?("No internet connection. Please try again.")
            case .notFound, .serverError, .serviceUnavailable:
                // Backend bookmark API not deployed yet - keep local state (don't revert)
                #if DEBUG
                print("[FeedSocialActions] Bookmark API not available (\(error)), using local state only")
                #endif
            default:
                // Revert on other errors
                onPostUpdate?(postId) { _ in currentPost }
                onError?("Failed to bookmark post. Please try again.")
                #if DEBUG
                print("[FeedSocialActions] Toggle bookmark error: \(error)")
                #endif
            }
            return false
        } catch {
            // Revert on unknown failure
            onPostUpdate?(postId) { _ in currentPost }
            onError?("Failed to bookmark post. Please try again.")
            #if DEBUG
            print("[FeedSocialActions] Toggle bookmark error: \(error)")
            #endif
            return false
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
