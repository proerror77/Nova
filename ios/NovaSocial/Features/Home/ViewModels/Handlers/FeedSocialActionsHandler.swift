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

    // MARK: - Server Confirmed State (source of truth for count calculations)

    /// Server-confirmed like state per post (isLiked, count) - source of truth for count calculations
    private var confirmedLikeState: [String: (isLiked: Bool, count: Int)] = [:]

    /// Server-confirmed bookmark state per post (isBookmarked, count)
    private var confirmedBookmarkState: [String: (isBookmarked: Bool, count: Int)] = [:]

    /// User's intended target state after rapid clicks
    private var pendingLikeTarget: [String: Bool] = [:]
    private var pendingBookmarkTarget: [String: Bool] = [:]

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
    /// Handles rapid clicks correctly by:
    /// 1. Tracking server-confirmed state separately from UI state
    /// 2. Calculating display count based on confirmed count (not cumulative)
    /// 3. Only sending API request if final state differs from confirmed state
    func toggleLike(postId: String, currentPost: FeedPost) async -> Bool {
        guard currentUserId != nil else {
            #if DEBUG
            print("[FeedSocialActions] toggleLike early return - userId is nil")
            #endif
            return false
        }

        // Initialize server-confirmed state if not set
        if confirmedLikeState[postId] == nil {
            confirmedLikeState[postId] = (currentPost.isLiked, currentPost.likeCount)
        }
        let confirmed = confirmedLikeState[postId]!

        // Calculate new target state by toggling current target (or confirmed if no pending)
        let currentTarget = pendingLikeTarget[postId] ?? confirmed.isLiked
        let newTarget = !currentTarget
        pendingLikeTarget[postId] = newTarget

        // Calculate display count based on CONFIRMED count, not current UI count
        // This prevents count drift during rapid clicking
        let displayCount: Int
        if newTarget == confirmed.isLiked {
            // Target same as confirmed → show confirmed count
            displayCount = confirmed.count
        } else if newTarget && !confirmed.isLiked {
            // Want to like, was not liked → confirmed + 1
            displayCount = confirmed.count + 1
        } else {
            // Want to unlike, was liked → confirmed - 1
            displayCount = max(0, confirmed.count - 1)
        }

        // Optimistic update with correct count
        onPostUpdate?(postId) { post in
            post.copying(likeCount: displayCount, isLiked: newTarget)
        }

        // Cancel any pending debounce task
        pendingLikeTasks[postId]?.cancel()

        // Create new debounced task
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.debounceDelay ?? 300_000_000)
            } catch {
                return // Cancelled
            }
            guard !Task.isCancelled else { return }
            await self?.performLikeOperation(postId: postId)
        }

        pendingLikeTasks[postId] = task
        return true
    }

    /// Perform the actual like/unlike API call after debounce
    private func performLikeOperation(postId: String) async {
        // Get target and confirmed states
        guard let targetLiked = pendingLikeTarget[postId],
              let confirmed = confirmedLikeState[postId] else {
            return
        }

        // Clear pending target
        pendingLikeTarget.removeValue(forKey: postId)

        // If target equals confirmed, no API call needed (user clicked even number of times)
        if targetLiked == confirmed.isLiked {
            #if DEBUG
            print("[FeedSocialActions] Like state unchanged, skipping API call for postId: \(postId)")
            #endif
            // Ensure UI shows confirmed count
            onPostUpdate?(postId) { post in
                post.copying(likeCount: confirmed.count, isLiked: confirmed.isLiked)
            }
            return
        }

        // Prevent concurrent operations
        guard !ongoingLikeOperations.contains(postId) else {
            #if DEBUG
            print("[FeedSocialActions] performLikeOperation skipped - already in progress for postId: \(postId)")
            #endif
            return
        }

        guard let userId = currentUserId else { return }

        ongoingLikeOperations.insert(postId)
        defer { ongoingLikeOperations.remove(postId) }

        do {
            let response: SocialService.LikeResponse
            if targetLiked {
                response = try await socialService.createLike(postId: postId, userId: userId)
            } else {
                response = try await socialService.deleteLike(postId: postId, userId: userId)
            }

            // Update confirmed state with server response
            confirmedLikeState[postId] = (targetLiked, Int(response.likeCount))

            // Update UI with accurate server count (only if no new pending operation)
            if pendingLikeTarget[postId] == nil {
                onPostUpdate?(postId) { post in
                    post.copying(likeCount: Int(response.likeCount), isLiked: targetLiked)
                }
            }

            await FeedCacheService.shared.invalidateCache()

            #if DEBUG
            print("[FeedSocialActions] Like operation completed for postId: \(postId), isLiked: \(targetLiked), count: \(response.likeCount)")
            #endif
        } catch let error as APIError {
            // Revert to confirmed state (only if no new pending operation)
            if pendingLikeTarget[postId] == nil {
                onPostUpdate?(postId) { post in
                    post.copying(likeCount: confirmed.count, isLiked: confirmed.isLiked)
                }
            }
            handleError(error, action: "like")
        } catch {
            // Revert to confirmed state (only if no new pending operation)
            if pendingLikeTarget[postId] == nil {
                onPostUpdate?(postId) { post in
                    post.copying(likeCount: confirmed.count, isLiked: confirmed.isLiked)
                }
            }
            onError?("Failed to like post. Please try again.")
            #if DEBUG
            print("[FeedSocialActions] Toggle like error: \(error)")
            #endif
        }
    }
    
    // MARK: - Bookmark Actions

    /// Toggle bookmark on a post with debouncing
    /// Same logic as toggleLike - tracks confirmed state and calculates count correctly
    func toggleBookmark(postId: String, currentPost: FeedPost) async -> Bool {
        guard currentUserId != nil else {
            #if DEBUG
            print("[FeedSocialActions] toggleBookmark early return - userId is nil")
            #endif
            return false
        }

        // Initialize server-confirmed state if not set
        if confirmedBookmarkState[postId] == nil {
            confirmedBookmarkState[postId] = (currentPost.isBookmarked, currentPost.bookmarkCount)
        }
        let confirmed = confirmedBookmarkState[postId]!

        // Calculate new target state
        let currentTarget = pendingBookmarkTarget[postId] ?? confirmed.isBookmarked
        let newTarget = !currentTarget
        pendingBookmarkTarget[postId] = newTarget

        // Calculate display count based on CONFIRMED count
        let displayCount: Int
        if newTarget == confirmed.isBookmarked {
            displayCount = confirmed.count
        } else if newTarget && !confirmed.isBookmarked {
            displayCount = confirmed.count + 1
        } else {
            displayCount = max(0, confirmed.count - 1)
        }

        // Optimistic update with correct count
        onPostUpdate?(postId) { post in
            post.copying(bookmarkCount: displayCount, isBookmarked: newTarget)
        }

        // Cancel any pending debounce task
        pendingBookmarkTasks[postId]?.cancel()

        // Create new debounced task
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.debounceDelay ?? 300_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.performBookmarkOperation(postId: postId)
        }

        pendingBookmarkTasks[postId] = task
        return true
    }

    /// Perform the actual bookmark/unbookmark API call after debounce
    private func performBookmarkOperation(postId: String) async {
        guard let targetBookmarked = pendingBookmarkTarget[postId],
              let confirmed = confirmedBookmarkState[postId] else {
            return
        }

        pendingBookmarkTarget.removeValue(forKey: postId)

        // Skip API if target equals confirmed
        if targetBookmarked == confirmed.isBookmarked {
            #if DEBUG
            print("[FeedSocialActions] Bookmark state unchanged, skipping API call for postId: \(postId)")
            #endif
            onPostUpdate?(postId) { post in
                post.copying(bookmarkCount: confirmed.count, isBookmarked: confirmed.isBookmarked)
            }
            return
        }

        guard !ongoingBookmarkOperations.contains(postId) else {
            #if DEBUG
            print("[FeedSocialActions] performBookmarkOperation skipped - already in progress for postId: \(postId)")
            #endif
            return
        }

        guard let userId = currentUserId else { return }

        ongoingBookmarkOperations.insert(postId)
        defer { ongoingBookmarkOperations.remove(postId) }

        do {
            if targetBookmarked {
                try await socialService.createBookmark(postId: postId, userId: userId)
            } else {
                try await socialService.deleteBookmark(postId: postId)
            }

            // Update confirmed state (bookmark API doesn't return count, so calculate it)
            let newCount = targetBookmarked ? confirmed.count + 1 : max(0, confirmed.count - 1)
            confirmedBookmarkState[postId] = (targetBookmarked, newCount)

            if pendingBookmarkTarget[postId] == nil {
                onPostUpdate?(postId) { post in
                    post.copying(bookmarkCount: newCount, isBookmarked: targetBookmarked)
                }
            }

            await FeedCacheService.shared.invalidateCache()

            #if DEBUG
            print("[FeedSocialActions] Bookmark operation completed for postId: \(postId), isBookmarked: \(targetBookmarked)")
            #endif
        } catch let error as APIError {
            switch error {
            case .unauthorized:
                if pendingBookmarkTarget[postId] == nil {
                    onPostUpdate?(postId) { post in
                        post.copying(bookmarkCount: confirmed.count, isBookmarked: confirmed.isBookmarked)
                    }
                }
                onError?("Please try again.")
            case .noConnection:
                if pendingBookmarkTarget[postId] == nil {
                    onPostUpdate?(postId) { post in
                        post.copying(bookmarkCount: confirmed.count, isBookmarked: confirmed.isBookmarked)
                    }
                }
                onError?("No internet connection. Please try again.")
            case .notFound, .serverError, .serviceUnavailable:
                // Backend bookmark API not deployed yet - keep local state
                let newCount = targetBookmarked ? confirmed.count + 1 : max(0, confirmed.count - 1)
                confirmedBookmarkState[postId] = (targetBookmarked, newCount)
                #if DEBUG
                print("[FeedSocialActions] Bookmark API not available (\(error)), using local state only")
                #endif
            default:
                if pendingBookmarkTarget[postId] == nil {
                    onPostUpdate?(postId) { post in
                        post.copying(bookmarkCount: confirmed.count, isBookmarked: confirmed.isBookmarked)
                    }
                }
                onError?("Failed to bookmark post. Please try again.")
            }
        } catch {
            if pendingBookmarkTarget[postId] == nil {
                onPostUpdate?(postId) { post in
                    post.copying(bookmarkCount: confirmed.count, isBookmarked: confirmed.isBookmarked)
                }
            }
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
