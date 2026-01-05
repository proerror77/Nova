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

    // MARK: - Debounce State

    /// Debounce delay in nanoseconds (300ms)
    private let debounceDelay: UInt64 = 300_000_000

    /// Pending debounced like tasks per post
    private var pendingLikeTasks: [String: Task<Void, Never>] = [:]

    /// Pending debounced bookmark tasks per post
    private var pendingBookmarkTasks: [String: Task<Void, Never>] = [:]

    /// Request sequence numbers to ignore stale responses
    private var likeRequestSequence: [String: Int] = [:]
    private var bookmarkRequestSequence: [String: Int] = [:]
    
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

    /// Toggle like on a post with debouncing
    /// - Parameters:
    ///   - postId: The post ID to like/unlike
    ///   - currentPost: The current post state
    /// - Returns: Whether the operation was initiated
    func toggleLike(postId: String, currentPost: FeedPost) async -> Bool {
        guard currentUserId != nil else {
            #if DEBUG
            print("[FeedSocialActions] toggleLike early return - userId is nil")
            #endif
            return false
        }

        let wasLiked = currentPost.isLiked

        // Optimistic update - immediate UI feedback
        onPostUpdate?(postId) { post in
            post.copying(
                likeCount: wasLiked ? max(0, post.likeCount - 1) : post.likeCount + 1,
                isLiked: !wasLiked
            )
        }

        // Cancel any pending debounce task for this post
        pendingLikeTasks[postId]?.cancel()

        // Increment request sequence
        let currentSequence = (likeRequestSequence[postId] ?? 0) + 1
        likeRequestSequence[postId] = currentSequence

        // Create new debounced task
        let task = Task { [weak self] in
            // Wait for debounce delay
            do {
                try await Task.sleep(nanoseconds: self?.debounceDelay ?? 300_000_000)
            } catch {
                // Task was cancelled (user clicked again)
                return
            }

            guard !Task.isCancelled else { return }

            // Execute the actual like operation
            await self?.performLikeOperation(
                postId: postId,
                originalPost: currentPost,
                targetLikedState: !wasLiked,
                requestSequence: currentSequence
            )
        }

        pendingLikeTasks[postId] = task
        return true
    }

    /// Perform the actual like/unlike API call
    private func performLikeOperation(
        postId: String,
        originalPost: FeedPost,
        targetLikedState: Bool,
        requestSequence: Int
    ) async {
        // Prevent concurrent like operations for the same post
        guard !ongoingLikeOperations.contains(postId) else {
            #if DEBUG
            print("[FeedSocialActions] performLikeOperation skipped - operation already in progress for postId: \(postId)")
            #endif
            return
        }

        guard let userId = currentUserId else { return }

        // Check if this request is still the latest
        guard likeRequestSequence[postId] == requestSequence else {
            #if DEBUG
            print("[FeedSocialActions] Stale like request ignored for postId: \(postId)")
            #endif
            return
        }

        ongoingLikeOperations.insert(postId)
        defer { ongoingLikeOperations.remove(postId) }

        do {
            let response: SocialService.LikeResponse
            if targetLikedState {
                // User wants to like
                response = try await socialService.createLike(postId: postId, userId: userId)
            } else {
                // User wants to unlike
                response = try await socialService.deleteLike(postId: postId, userId: userId)
            }

            // Check again if this is still the latest request before updating UI
            guard likeRequestSequence[postId] == requestSequence else { return }

            // Reconcile with server's accurate count
            onPostUpdate?(postId) { post in
                post.copying(
                    likeCount: Int(response.likeCount),
                    isLiked: targetLikedState
                )
            }

            // Invalidate feed cache on successful like/unlike
            await FeedCacheService.shared.invalidateCache()

            #if DEBUG
            print("[FeedSocialActions] Like operation completed for postId: \(postId), isLiked: \(targetLikedState)")
            #endif
        } catch let error as APIError {
            // Check if this is still the latest request before reverting
            guard likeRequestSequence[postId] == requestSequence else { return }

            // Revert on failure
            onPostUpdate?(postId) { _ in originalPost }
            handleError(error, action: "like")
        } catch {
            // Check if this is still the latest request before reverting
            guard likeRequestSequence[postId] == requestSequence else { return }

            // Revert on failure
            onPostUpdate?(postId) { _ in originalPost }
            onError?("Failed to like post. Please try again.")
            #if DEBUG
            print("[FeedSocialActions] Toggle like error: \(error)")
            #endif
        }
    }
    
    // MARK: - Bookmark Actions

    /// Toggle bookmark on a post with debouncing
    /// - Parameters:
    ///   - postId: The post ID to bookmark/unbookmark
    ///   - currentPost: The current post state
    /// - Returns: Whether the operation was initiated
    func toggleBookmark(postId: String, currentPost: FeedPost) async -> Bool {
        guard currentUserId != nil else {
            #if DEBUG
            print("[FeedSocialActions] toggleBookmark early return - userId is nil")
            #endif
            return false
        }

        let wasBookmarked = currentPost.isBookmarked

        // Optimistic update - immediate UI feedback
        onPostUpdate?(postId) { post in
            post.copying(
                bookmarkCount: wasBookmarked ? max(0, post.bookmarkCount - 1) : post.bookmarkCount + 1,
                isBookmarked: !wasBookmarked
            )
        }

        // Cancel any pending debounce task for this post
        pendingBookmarkTasks[postId]?.cancel()

        // Increment request sequence
        let currentSequence = (bookmarkRequestSequence[postId] ?? 0) + 1
        bookmarkRequestSequence[postId] = currentSequence

        // Create new debounced task
        let task = Task { [weak self] in
            // Wait for debounce delay
            do {
                try await Task.sleep(nanoseconds: self?.debounceDelay ?? 300_000_000)
            } catch {
                // Task was cancelled (user clicked again)
                return
            }

            guard !Task.isCancelled else { return }

            // Execute the actual bookmark operation
            await self?.performBookmarkOperation(
                postId: postId,
                originalPost: currentPost,
                targetBookmarkedState: !wasBookmarked,
                requestSequence: currentSequence
            )
        }

        pendingBookmarkTasks[postId] = task
        return true
    }

    /// Perform the actual bookmark/unbookmark API call
    private func performBookmarkOperation(
        postId: String,
        originalPost: FeedPost,
        targetBookmarkedState: Bool,
        requestSequence: Int
    ) async {
        // Prevent concurrent bookmark operations for the same post
        guard !ongoingBookmarkOperations.contains(postId) else {
            #if DEBUG
            print("[FeedSocialActions] performBookmarkOperation skipped - operation already in progress for postId: \(postId)")
            #endif
            return
        }

        guard let userId = currentUserId else { return }

        // Check if this request is still the latest
        guard bookmarkRequestSequence[postId] == requestSequence else {
            #if DEBUG
            print("[FeedSocialActions] Stale bookmark request ignored for postId: \(postId)")
            #endif
            return
        }

        ongoingBookmarkOperations.insert(postId)
        defer { ongoingBookmarkOperations.remove(postId) }

        do {
            if targetBookmarkedState {
                try await socialService.createBookmark(postId: postId, userId: userId)
            } else {
                try await socialService.deleteBookmark(postId: postId)
            }

            // Check again if this is still the latest request
            guard bookmarkRequestSequence[postId] == requestSequence else { return }

            // Invalidate feed cache on successful bookmark/unbookmark
            await FeedCacheService.shared.invalidateCache()

            #if DEBUG
            print("[FeedSocialActions] Bookmark operation completed for postId: \(postId), isBookmarked: \(targetBookmarkedState)")
            #endif
        } catch let error as APIError {
            // Check if this is still the latest request before handling error
            guard bookmarkRequestSequence[postId] == requestSequence else { return }

            // Handle specific error cases
            switch error {
            case .unauthorized:
                onPostUpdate?(postId) { _ in originalPost }
                onError?("Please try again.")
                #if DEBUG
                print("[FeedSocialActions] Toggle bookmark error: Unauthorized")
                #endif
            case .noConnection:
                onPostUpdate?(postId) { _ in originalPost }
                onError?("No internet connection. Please try again.")
            case .notFound, .serverError, .serviceUnavailable:
                // Backend bookmark API not deployed yet - keep local state (don't revert)
                #if DEBUG
                print("[FeedSocialActions] Bookmark API not available (\(error)), using local state only")
                #endif
            default:
                onPostUpdate?(postId) { _ in originalPost }
                onError?("Failed to bookmark post. Please try again.")
                #if DEBUG
                print("[FeedSocialActions] Toggle bookmark error: \(error)")
                #endif
            }
        } catch {
            // Check if this is still the latest request before reverting
            guard bookmarkRequestSequence[postId] == requestSequence else { return }

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
