import Foundation

/// Handles post processing, transformation, and enrichment for feed
/// Extracted from FeedViewModel to follow Single Responsibility Principle
@MainActor
final class FeedPostProcessor {
    // MARK: - Dependencies
    
    private let socialService: SocialService
    private let feedService: FeedService
    private let authManager: AuthenticationManager
    
    // MARK: - Computed Properties
    
    private var isAuthenticated: Bool {
        authManager.isAuthenticated && !authManager.isGuestMode
    }
    
    // MARK: - Init
    
    init(
        socialService: SocialService = SocialService(),
        feedService: FeedService = FeedService(),
        authManager: AuthenticationManager = AuthenticationManager.shared
    ) {
        self.socialService = socialService
        self.feedService = feedService
        self.authManager = authManager
    }
    
    // MARK: - Post Processing Pipeline

    /// Process posts: sync current user profile, enrich with like and bookmark status, and deduplicate
    func processAndDeduplicatePosts(_ posts: [FeedPost]) async -> [FeedPost] {
        let syncedPosts = syncCurrentUserProfile(posts)
        let likeEnrichedPosts = await enrichWithLikeStatus(syncedPosts)
        let bookmarkEnrichedPosts = await enrichWithBookmarkStatus(likeEnrichedPosts)
        return deduplicatePosts(bookmarkEnrichedPosts)
    }
    
    /// Sync current user's name/avatar for their own posts
    /// This ensures the Feed shows the latest profile data after user updates it locally
    func syncCurrentUserProfile(_ posts: [FeedPost]) -> [FeedPost] {
        guard let currentUser = authManager.currentUser else {
            return posts
        }
        
        let resolvedName: String = {
            let display = currentUser.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !display.isEmpty {
                return display
            }
            return currentUser.username
        }()
        
        return posts.map { post in
            guard post.authorId == currentUser.id else { return post }
            
            let nameOverride: String? = resolvedName.isEmpty ? nil : resolvedName
            let avatarOverride: String?? = {
                if currentUser.avatarUrl != post.authorAvatar {
                    return .some(currentUser.avatarUrl)
                }
                return nil
            }()
            
            if nameOverride == nil && avatarOverride == nil {
                return post
            }
            
            return post.copying(authorName: nameOverride, authorAvatar: avatarOverride)
        }
    }

    /// Enrich posts with like status for authenticated users (fixes isLiked inconsistency after refresh)
    /// Also ensures likeCount is at least 1 when user has liked the post (fixes count mismatch)
    func enrichWithLikeStatus(_ posts: [FeedPost]) async -> [FeedPost] {
        guard isAuthenticated, !posts.isEmpty else { return posts }

        let postIds = posts.map { $0.id }
        guard let likedIds = try? await socialService.batchCheckLiked(postIds: postIds) else {
            return posts
        }

        #if DEBUG
        print("[FeedPostProcessor] Enriched like status: \(likedIds.count) liked out of \(posts.count) posts")
        #endif

        return posts.map { post in
            let userLikedThis = likedIds.contains(post.id)

            if userLikedThis {
                // User liked this post - ensure isLiked=true AND likeCount >= 1
                let correctedCount = max(post.likeCount, 1)
                if post.isLiked && post.likeCount >= 1 {
                    return post  // Already correct, no change needed
                }
                #if DEBUG
                if post.likeCount == 0 {
                    print("[FeedPostProcessor] ⚠️ Correcting likeCount: post \(post.id) was 0, now 1")
                }
                #endif
                return post.copying(likeCount: correctedCount, isLiked: true)
            } else {
                // User did NOT like this post - ensure isLiked=false
                // Don't decrease count (other users may have liked it)
                if post.isLiked {
                    return post.copying(isLiked: false)
                }
                return post
            }
        }
    }

    /// Enrich posts with bookmark status for authenticated users
    func enrichWithBookmarkStatus(_ posts: [FeedPost]) async -> [FeedPost] {
        guard isAuthenticated, !posts.isEmpty else { return posts }
        
        let postIds = posts.map { $0.id }
        guard let bookmarkedIds = try? await socialService.batchCheckBookmarked(postIds: postIds) else {
            return posts
        }
        
        return posts.map { post in
            bookmarkedIds.contains(post.id) ? post.copying(isBookmarked: true) : post
        }
    }
    
    /// Remove duplicate posts by ID
    func deduplicatePosts(_ posts: [FeedPost]) -> [FeedPost] {
        var seenIds = Set<String>()
        return posts.filter { post in
            guard !seenIds.contains(post.id) else { return false }
            seenIds.insert(post.id)
            return true
        }
    }
    
    /// Merge recently created posts that are not in the server response
    func mergeRecentlyCreatedPosts(
        into posts: inout [FeedPost],
        recentPosts: [(post: FeedPost, createdAt: Date)],
        retentionDuration: TimeInterval
    ) {
        let now = Date()
        let validRecentPosts = recentPosts.filter { now.timeIntervalSince($0.createdAt) <= retentionDuration }
        
        let serverPostIds = Set(posts.map { $0.id })
        let missingPosts = validRecentPosts
            .filter { !serverPostIds.contains($0.post.id) }
            .map { $0.post }
        
        if !missingPosts.isEmpty {
            // Insert missing recent posts at the top
            posts.insert(contentsOf: missingPosts, at: 0)
            #if DEBUG
            print("[FeedPostProcessor] Preserved \(missingPosts.count) recently created post(s) after refresh")
            #endif
        }
    }
    
    // MARK: - Author Profile Updates
    
    /// Update posts with fetched author profiles
    func updateAuthorProfiles(_ profiles: [String: AuthorProfile], in posts: inout [FeedPost]) {
        guard !profiles.isEmpty else { return }
        
        for i in posts.indices {
            let post = posts[i]
            if let profile = profiles[post.authorId] {
                posts[i] = post.copying(
                    authorName: profile.displayName,
                    authorAvatar: .some(profile.avatarUrl)
                )
            }
        }
    }
    
    /// Update bookmark states for posts
    func updateBookmarkStates(_ bookmarkedIds: Set<String>, in posts: inout [FeedPost]) {
        for i in posts.indices {
            if bookmarkedIds.contains(posts[i].id) && !posts[i].isBookmarked {
                posts[i] = posts[i].copying(isBookmarked: true)
            }
        }
    }

    // MARK: - Async Background Updates

    /// Load bookmark status asynchronously without blocking the main feed display
    func loadBookmarkStatusAsync(
        for postIds: [String],
        onComplete: @escaping (Set<String>) -> Void
    ) {
        guard isAuthenticated, !postIds.isEmpty else { return }
        
        Task(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                let bookmarkedIds = try await self.socialService.batchCheckBookmarked(postIds: postIds)
                await MainActor.run {
                    onComplete(bookmarkedIds)
                }
                
                #if DEBUG
                print("[FeedPostProcessor] Async bookmark load complete: \(bookmarkedIds.count) bookmarked")
                #endif
            } catch {
                #if DEBUG
                print("[FeedPostProcessor] Async bookmark load failed: \(error)")
                #endif
                // Silently fail - bookmarks are non-critical for feed display
            }
        }
    }
    
    /// Fetch missing author profiles and update posts
    func fetchMissingAuthorProfilesAsync(
        for posts: [FeedPost],
        onComplete: @escaping ([String: AuthorProfile]) -> Void
    ) {
        guard isAuthenticated else { return }
        
        // Find posts with missing author info (placeholder name or missing avatar)
        let postsWithMissingProfiles = posts.filter { post in
            post.authorName.isEmpty ||
            post.authorName.hasPrefix("User ") ||
            post.authorAvatar == nil
        }
        
        guard !postsWithMissingProfiles.isEmpty else { return }
        
        let userIds = postsWithMissingProfiles.map { $0.authorId }
        
        #if DEBUG
        print("[FeedPostProcessor] Fetching \(userIds.count) missing author profiles")
        #endif
        
        Task(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                let profiles = try await self.feedService.batchGetProfiles(userIds: userIds)
                await MainActor.run {
                    onComplete(profiles)
                }
                
                #if DEBUG
                print("[FeedPostProcessor] Updated \(profiles.count) author profiles")
                #endif
            } catch {
                #if DEBUG
                print("[FeedPostProcessor] Failed to fetch author profiles: \(error)")
                #endif
                // Silently fail - placeholder names are acceptable fallback
            }
        }
    }
}
