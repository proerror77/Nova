import Foundation

/// Local cache for like/bookmark states
/// Persists user interactions locally for instant UI feedback
/// Similar to Instagram/小红书's approach: local cache + server sync
@MainActor
final class LikeCache {
    // MARK: - Singleton
    static let shared = LikeCache()

    // MARK: - Storage Keys
    private let likedPostsKey = "cached_liked_posts"
    private let bookmarkedPostsKey = "cached_bookmarked_posts"
    private let likeCountsKey = "cached_like_counts"

    // MARK: - In-Memory Cache (for fast access)
    private var likedPosts: Set<String> = []
    private var bookmarkedPosts: Set<String> = []
    private var likeCounts: [String: Int] = [:]

    // MARK: - Init
    private init() {
        loadFromDisk()
    }

    // MARK: - Like Operations

    /// Check if a post is liked (from local cache)
    func isLiked(postId: String) -> Bool {
        likedPosts.contains(postId)
    }

    /// Set like state for a post
    func setLiked(postId: String, isLiked: Bool) {
        if isLiked {
            likedPosts.insert(postId)
        } else {
            likedPosts.remove(postId)
        }
        saveToDisk()

        #if DEBUG
        print("[LikeCache] 💾 setLiked(\(postId.prefix(8))): \(isLiked), total cached: \(likedPosts.count)")
        #endif
    }

    /// Get like count for a post (from local cache)
    func getLikeCount(postId: String) -> Int? {
        likeCounts[postId]
    }

    /// Set like count for a post
    func setLikeCount(postId: String, count: Int) {
        likeCounts[postId] = count
        saveToDisk()
    }

    // MARK: - Bookmark Operations

    /// Check if a post is bookmarked (from local cache)
    func isBookmarked(postId: String) -> Bool {
        bookmarkedPosts.contains(postId)
    }

    /// Set bookmark state for a post
    func setBookmarked(postId: String, isBookmarked: Bool) {
        if isBookmarked {
            bookmarkedPosts.insert(postId)
        } else {
            bookmarkedPosts.remove(postId)
        }
        saveToDisk()

        #if DEBUG
        print("[LikeCache] 💾 setBookmarked(\(postId.prefix(8))): \(isBookmarked)")
        #endif
    }

    // MARK: - Batch Operations

    /// Update cache from server response (reconcile)
    func updateFromServerResponse(posts: [FeedPost]) {
        for post in posts {
            if post.isLiked {
                likedPosts.insert(post.id)
            }
            if post.isBookmarked {
                bookmarkedPosts.insert(post.id)
            }
            likeCounts[post.id] = post.likeCount
        }
        saveToDisk()

        #if DEBUG
        print("[LikeCache] 📥 Updated from server: \(posts.count) posts")
        #endif
    }

    /// Apply cached states to posts (for instant UI)
    func applyCachedStates(to posts: inout [FeedPost]) {
        for i in posts.indices {
            let postId = posts[i].id

            // Apply cached like state if we have it
            if likedPosts.contains(postId) && !posts[i].isLiked {
                posts[i] = posts[i].copying(isLiked: true)
            }

            // Apply cached bookmark state if we have it
            if bookmarkedPosts.contains(postId) && !posts[i].isBookmarked {
                posts[i] = posts[i].copying(isBookmarked: true)
            }

            // Apply cached like count if we have it and it's higher
            if let cachedCount = likeCounts[postId], cachedCount > posts[i].likeCount {
                posts[i] = posts[i].copying(likeCount: cachedCount)
            }
        }

        #if DEBUG
        print("[LikeCache] ✨ Applied cached states to \(posts.count) posts")
        #endif
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        let defaults = UserDefaults.standard

        if let likedArray = defaults.array(forKey: likedPostsKey) as? [String] {
            likedPosts = Set(likedArray)
        }

        if let bookmarkedArray = defaults.array(forKey: bookmarkedPostsKey) as? [String] {
            bookmarkedPosts = Set(bookmarkedArray)
        }

        if let counts = defaults.dictionary(forKey: likeCountsKey) as? [String: Int] {
            likeCounts = counts
        }

        #if DEBUG
        print("[LikeCache] 📂 Loaded from disk: \(likedPosts.count) likes, \(bookmarkedPosts.count) bookmarks")
        #endif
    }

    private func saveToDisk() {
        let defaults = UserDefaults.standard
        defaults.set(Array(likedPosts), forKey: likedPostsKey)
        defaults.set(Array(bookmarkedPosts), forKey: bookmarkedPostsKey)
        defaults.set(likeCounts, forKey: likeCountsKey)
    }

    // MARK: - Cleanup

    /// Clear all cached data (e.g., on logout)
    func clearAll() {
        likedPosts.removeAll()
        bookmarkedPosts.removeAll()
        likeCounts.removeAll()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: likedPostsKey)
        defaults.removeObject(forKey: bookmarkedPostsKey)
        defaults.removeObject(forKey: likeCountsKey)

        #if DEBUG
        print("[LikeCache] 🗑️ Cleared all cached data")
        #endif
    }

    /// Prune old entries to prevent unbounded growth
    /// Call periodically (e.g., on app launch)
    func pruneOldEntries(keepCount: Int = 500) {
        // Keep only the most recent entries
        // In a real app, you'd track timestamps and prune by age
        if likedPosts.count > keepCount {
            let toRemove = likedPosts.count - keepCount
            for _ in 0..<toRemove {
                if let first = likedPosts.first {
                    likedPosts.remove(first)
                }
            }
        }

        if likeCounts.count > keepCount {
            // Remove oldest entries (simplified - in production use LRU)
            let toRemove = likeCounts.count - keepCount
            let keysToRemove = Array(likeCounts.keys.prefix(toRemove))
            for key in keysToRemove {
                likeCounts.removeValue(forKey: key)
            }
        }

        saveToDisk()
    }
}
