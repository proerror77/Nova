import Foundation
import os.log

private let socialActionsLogger = Logger(subsystem: "com.app.icered.pro", category: "SocialActions")

/// Handles social interactions (like, bookmark, share) for feed posts
/// Extracted from FeedViewModel to follow Single Responsibility Principle
@MainActor
final class FeedSocialActionsHandler {
    // MARK: - Instance Tracking (for debugging)

    private let instanceId = UUID().uuidString.prefix(8)

    // MARK: - Dependencies

    private let socialService: SocialService
    private let authManager: AuthenticationManager

    // MARK: - State

    /// Track ongoing like operations to prevent concurrent calls for the same post
    private var ongoingLikeOperations: Set<String> = []

    /// Track ongoing bookmark operations to prevent concurrent calls for the same post
    private var ongoingBookmarkOperations: Set<String> = []

    // MARK: - Debounce State (Xiaohongshu-style)

    /// Debounce delay in seconds - wait this long after last click before sending API request
    private let debounceDelay: TimeInterval = 0.3

    /// Pending like API tasks per post - cancelled when new click arrives
    private var pendingLikeTasks: [String: Task<Void, Never>] = [:]

    /// Pending bookmark API tasks per post - cancelled when new click arrives
    private var pendingBookmarkTasks: [String: Task<Void, Never>] = [:]

    /// Track pending UI state for likes (isLiked, likeCount) - used when rapid clicks occur
    /// This ensures each click builds on the previous click's state, not stale view state
    private var pendingLikeUIState: [String: (isLiked: Bool, count: Int)] = [:]

    /// Track pending UI state for bookmarks (isBookmarked, bookmarkCount)
    private var pendingBookmarkUIState: [String: (isBookmarked: Bool, count: Int)] = [:]

    // MARK: - Generation Tracking (prevent stale API responses)

    /// Generation number for like operations per post - increments on each new operation
    private var likeGeneration: [String: Int] = [:]

    /// Generation number for bookmark operations per post
    private var bookmarkGeneration: [String: Int] = [:]

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
        authManager: AuthenticationManager? = nil
    ) {
        self.socialService = socialService
        // Use provided authManager or fall back to shared instance (evaluated on MainActor)
        self.authManager = authManager ?? AuthenticationManager.shared
        socialActionsLogger.info("🆕 FeedSocialActionsHandler created | instanceId=\(self.instanceId)")
    }
    
    // MARK: - Like Actions

    /// Toggle like on a post with debounce (Xiaohongshu-style)
    /// - Every click: immediately updates UI
    /// - Debounces API calls: waits for clicks to settle, then sends final state
    /// - Cancels pending API tasks when new click arrives
    /// - Uses internal state tracking to handle rapid clicks correctly
    /// - Note: This is intentionally synchronous to prevent race conditions from async interleaving
    func toggleLike(postId: String, currentPost: FeedPost) -> Bool {
        // Log entry state for debugging rapid clicks
        let entryPendingState = pendingLikeUIState[postId]
        socialActionsLogger.info("❤️ toggleLike ENTRY | handler=\(self.instanceId) | postId=\(postId.prefix(8)) | pendingState=\(entryPendingState.map { "(\($0.isLiked),\($0.count))" } ?? "nil") | viewPost=(\(currentPost.isLiked),\(currentPost.likeCount))")

        guard currentUserId != nil else {
            socialActionsLogger.warning("toggleLike early return - userId is nil")
            return false
        }

        // Cancel any pending like API task for this post
        pendingLikeTasks[postId]?.cancel()
        pendingLikeTasks[postId] = nil

        // Increment generation for this post's like operations
        let currentGen = (likeGeneration[postId] ?? 0) + 1
        likeGeneration[postId] = currentGen

        // CRITICAL: Use pending UI state if exists (for rapid clicks), otherwise use view's state
        // This ensures each click builds on the previous click's result, not stale view state
        let (wasLiked, currentCount): (Bool, Int)
        let usedPendingState: Bool
        if let pending = pendingLikeUIState[postId] {
            wasLiked = pending.isLiked
            currentCount = pending.count
            usedPendingState = true
        } else {
            wasLiked = currentPost.isLiked
            currentCount = currentPost.likeCount
            usedPendingState = false
        }

        // Calculate new state - toggle from the ACTUAL current state
        let newLikedState = !wasLiked
        let newLikeCount = wasLiked ? max(0, currentCount - 1) : currentCount + 1

        socialActionsLogger.info("❤️ toggleLike gen:\(currentGen) | usedPending:\(usedPendingState) | was:\(wasLiked)/\(currentCount) → new:\(newLikedState)/\(newLikeCount) | viewState:\(currentPost.isLiked)/\(currentPost.likeCount)")

        // Update pending UI state for next rapid click
        pendingLikeUIState[postId] = (isLiked: newLikedState, count: newLikeCount)

        // Optimistic update - immediate UI feedback (every click updates UI)
        onPostUpdate?(postId) { post in
            post.copying(likeCount: newLikeCount, isLiked: newLikedState)
        }

        // Capture original post state for potential revert (before any clicks in this sequence)
        let originalPost = currentPost

        // Schedule debounced API call
        // Use @MainActor to ensure Task runs on main actor (Swift 6 compatibility)
        let task = Task { @MainActor [weak self] in
            // Wait for debounce delay
            try? await Task.sleep(nanoseconds: UInt64(self?.debounceDelay ?? 0.3) * 1_000_000_000)

            // Check if task was cancelled (newer click arrived)
            guard !Task.isCancelled else { return }

            // Get the final target state after all clicks settled
            guard let self = self else { return }
            guard self.likeGeneration[postId] == currentGen else { return }
            guard let finalState = self.pendingLikeUIState[postId] else {
                self.pendingLikeTasks.removeValue(forKey: postId)
                return
            }

            // Clean up pending state before calling API to allow server response updates
            socialActionsLogger.info("❤️ Clearing pendingLikeUIState for postId: \(postId)")
            self.pendingLikeUIState.removeValue(forKey: postId)
            self.pendingLikeTasks.removeValue(forKey: postId)

            // Only send API if target state differs from original state
            if finalState.isLiked != originalPost.isLiked {
                await self.performLikeOperation(
                    postId: postId,
                    originalPost: originalPost,
                    targetLikedState: finalState.isLiked,
                    generation: currentGen
                )
            }
        }

        pendingLikeTasks[postId] = task

        return true
    }

    /// Perform the actual like/unlike API call
    /// - Parameter generation: The generation number when this operation was initiated
    private func performLikeOperation(
        postId: String,
        originalPost: FeedPost,
        targetLikedState: Bool,
        generation: Int
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

            // Only update UI if this is still the latest operation AND no new pending clicks
            guard likeGeneration[postId] == generation else {
                socialActionsLogger.info("Ignoring stale like response for postId: \(postId), gen: \(generation), current: \(self.likeGeneration[postId] ?? -1)")
                return
            }

            // Update UI with server's accurate count (safe because no new clicks are pending)
            socialActionsLogger.info("❤️ API response: count=\(response.likeCount), updating UI")
            onPostUpdate?(postId) { post in
                post.copying(likeCount: Int(response.likeCount), isLiked: targetLikedState)
            }

            await FeedCacheService.shared.invalidateCache()

            socialActionsLogger.info("Like operation completed for postId: \(postId), isLiked: \(targetLikedState), count: \(response.likeCount)")
        } catch let error as APIError {
            // Only revert if this is still the latest operation
            guard likeGeneration[postId] == generation else { return }
            onPostUpdate?(postId) { _ in originalPost }
            handleError(error, action: "like")
        } catch {
            // Only revert if this is still the latest operation
            guard likeGeneration[postId] == generation else { return }
            onPostUpdate?(postId) { _ in originalPost }
            onError?("Failed to like post. Please try again.")
            socialActionsLogger.error("Toggle like error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Bookmark Actions

    /// Toggle bookmark on a post with debounce (Xiaohongshu-style)
    /// - Every click: immediately updates UI
    /// - Debounces API calls: waits for clicks to settle, then sends final state
    /// - Cancels pending API tasks when new click arrives
    /// - Uses internal state tracking to handle rapid clicks correctly
    /// - Note: This is intentionally synchronous to prevent race conditions from async interleaving
    func toggleBookmark(postId: String, currentPost: FeedPost) -> Bool {
        guard currentUserId != nil else {
            socialActionsLogger.warning("toggleBookmark early return - userId is nil")
            return false
        }

        // Cancel any pending bookmark API task for this post
        pendingBookmarkTasks[postId]?.cancel()
        pendingBookmarkTasks[postId] = nil

        // Increment generation for this post's bookmark operations
        let currentGen = (bookmarkGeneration[postId] ?? 0) + 1
        bookmarkGeneration[postId] = currentGen

        // CRITICAL: Use pending UI state if exists (for rapid clicks), otherwise use view's state
        // This ensures each click builds on the previous click's result, not stale view state
        let (wasBookmarked, currentCount): (Bool, Int)
        let usedPendingState: Bool
        if let pending = pendingBookmarkUIState[postId] {
            wasBookmarked = pending.isBookmarked
            currentCount = pending.count
            usedPendingState = true
        } else {
            wasBookmarked = currentPost.isBookmarked
            currentCount = currentPost.bookmarkCount
            usedPendingState = false
        }

        // Calculate new state - toggle from the ACTUAL current state
        let newBookmarkedState = !wasBookmarked
        let newBookmarkCount = wasBookmarked ? max(0, currentCount - 1) : currentCount + 1

        socialActionsLogger.info("🔖 toggleBookmark gen:\(currentGen) | usedPending:\(usedPendingState) | was:\(wasBookmarked)/\(currentCount) → new:\(newBookmarkedState)/\(newBookmarkCount)")

        // Update pending UI state for next rapid click
        pendingBookmarkUIState[postId] = (isBookmarked: newBookmarkedState, count: newBookmarkCount)

        // Optimistic update - immediate UI feedback (every click updates UI)
        onPostUpdate?(postId) { post in
            post.copying(bookmarkCount: newBookmarkCount, isBookmarked: newBookmarkedState)
        }

        // Capture original post state for potential revert (before any clicks in this sequence)
        let originalPost = currentPost

        // Schedule debounced API call
        // Use @MainActor to ensure Task runs on main actor (Swift 6 compatibility)
        let task = Task { @MainActor [weak self] in
            // Wait for debounce delay
            try? await Task.sleep(nanoseconds: UInt64(self?.debounceDelay ?? 0.3) * 1_000_000_000)

            // Check if task was cancelled (newer click arrived)
            guard !Task.isCancelled else { return }

            // Get the final target state after all clicks settled
            guard let self = self,
                  let finalState = self.pendingBookmarkUIState[postId] else { return }

            // Only send API if target state differs from original state
            if finalState.isBookmarked != originalPost.isBookmarked {
                await self.performBookmarkOperation(
                    postId: postId,
                    originalPost: originalPost,
                    targetBookmarkedState: finalState.isBookmarked,
                    generation: currentGen
                )
            }

            // Clean up pending state
            socialActionsLogger.info("🔖 Clearing pendingBookmarkUIState for postId: \(postId)")
            self.pendingBookmarkUIState.removeValue(forKey: postId)
            self.pendingBookmarkTasks.removeValue(forKey: postId)
        }

        pendingBookmarkTasks[postId] = task

        return true
    }

    /// Perform the actual bookmark/unbookmark API call
    /// - Parameter generation: The generation number when this operation was initiated
    private func performBookmarkOperation(
        postId: String,
        originalPost: FeedPost,
        targetBookmarkedState: Bool,
        generation: Int
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

            // Only proceed if this is still the latest operation
            guard bookmarkGeneration[postId] == generation else {
                socialActionsLogger.info("Ignoring stale bookmark response for postId: \(postId), gen: \(generation), current: \(self.bookmarkGeneration[postId] ?? -1)")
                return
            }

            await FeedCacheService.shared.invalidateCache()

            socialActionsLogger.info("🔖 Bookmark operation completed for postId: \(postId), isBookmarked: \(targetBookmarkedState)")
        } catch let error as APIError {
            switch error {
            case .notFound, .serverError, .serviceUnavailable:
                // Backend bookmark API not deployed yet - keep local state
                socialActionsLogger.info("Bookmark API not available (\(error)), using local state only")
            default:
                // Only revert if this is still the latest operation
                guard bookmarkGeneration[postId] == generation else { return }
                onPostUpdate?(postId) { _ in originalPost }
                handleError(error, action: "bookmark")
            }
        } catch {
            // Only revert if this is still the latest operation
            guard bookmarkGeneration[postId] == generation else { return }
            onPostUpdate?(postId) { _ in originalPost }
            onError?("Failed to bookmark post. Please try again.")
            socialActionsLogger.error("Toggle bookmark error: \(error.localizedDescription)")
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
