import Foundation

/// Handles memory management for feed posts
/// Prevents excessive memory usage in long scrolling sessions
/// Extracted from FeedViewModel to follow Single Responsibility Principle
@MainActor
final class FeedMemoryManager {
    // MARK: - Configuration
    
    /// Maximum number of posts to keep in memory
    let maxPostsInMemory: Int
    
    /// Duration to keep recently created posts (for optimistic updates)
    let recentPostRetentionDuration: TimeInterval
    
    // MARK: - State
    
    /// Track recently created posts to preserve them after refresh (optimistic update)
    private(set) var recentlyCreatedPosts: [(post: FeedPost, createdAt: Date)] = []
    
    // MARK: - Init
    
    init(
        maxPostsInMemory: Int = 100,
        recentPostRetentionDuration: TimeInterval = 300 // 5 minutes
    ) {
        self.maxPostsInMemory = maxPostsInMemory
        self.recentPostRetentionDuration = recentPostRetentionDuration
    }
    
    // MARK: - Memory Limit Enforcement
    
    /// Enforce memory limit by removing oldest posts when exceeding maxPostsInMemory
    /// - Parameters:
    ///   - posts: Posts array to trim (inout)
    ///   - postIds: Post IDs array to trim (inout)
    /// - Returns: Number of posts removed
    @discardableResult
    func enforceMemoryLimit(posts: inout [FeedPost], postIds: inout [String]) -> Int {
        guard posts.count > maxPostsInMemory else { return 0 }
        
        let excessCount = posts.count - maxPostsInMemory
        
        // Remove oldest posts (from the end of the array)
        posts.removeLast(excessCount)
        postIds.removeLast(excessCount)
        
        #if DEBUG
        print("[FeedMemoryManager] Enforced memory limit: removed \(excessCount) oldest posts, now at \(posts.count) posts")
        #endif
        
        return excessCount
    }
    
    // MARK: - Recently Created Posts Management
    
    /// Add a recently created post for preservation after refresh
    func addRecentlyCreatedPost(_ post: FeedPost) {
        cleanupExpiredRecentPosts()
        recentlyCreatedPosts.append((post: post, createdAt: Date()))
    }
    
    /// Clean up expired recently created posts
    func cleanupExpiredRecentPosts() {
        let now = Date()
        recentlyCreatedPosts.removeAll { 
            now.timeIntervalSince($0.createdAt) > recentPostRetentionDuration 
        }
    }
    
    /// Get posts that should be preserved after refresh
    /// - Parameter serverPostIds: Set of post IDs returned from server
    /// - Returns: Array of posts missing from server response
    func getMissingRecentPosts(serverPostIds: Set<String>) -> [FeedPost] {
        cleanupExpiredRecentPosts()
        
        return recentlyCreatedPosts
            .filter { !serverPostIds.contains($0.post.id) }
            .map { $0.post }
    }
    
    /// Clear all recently created posts
    func clearRecentlyCreatedPosts() {
        recentlyCreatedPosts.removeAll()
    }
    
    // MARK: - Memory Statistics
    
    /// Get current memory usage statistics
    var memoryStats: MemoryStats {
        MemoryStats(
            recentPostsCount: recentlyCreatedPosts.count,
            maxPostsInMemory: maxPostsInMemory,
            retentionDuration: recentPostRetentionDuration
        )
    }
}

// MARK: - Memory Stats

extension FeedMemoryManager {
    struct MemoryStats {
        let recentPostsCount: Int
        let maxPostsInMemory: Int
        let retentionDuration: TimeInterval
        
        var description: String {
            "Recent posts: \(recentPostsCount), Max posts: \(maxPostsInMemory), Retention: \(Int(retentionDuration))s"
        }
    }
}
