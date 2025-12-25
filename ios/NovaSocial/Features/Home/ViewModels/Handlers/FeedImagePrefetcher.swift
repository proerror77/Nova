import Foundation

/// Handles image prefetching for feed posts to improve scroll performance
/// Extracted from FeedViewModel to follow Single Responsibility Principle
@MainActor
final class FeedImagePrefetcher {
    // MARK: - Configuration
    
    /// Target size for prefetched images
    private let prefetchTargetSize = CGSize(width: 750, height: 1000)
    
    /// Debounce interval to prevent excessive prefetch calls during rapid scrolling
    private let prefetchDebounceInterval: TimeInterval = 0.5
    
    /// Maximum number of retries for failed prefetch URLs
    private let maxPrefetchRetries = 2
    
    // MARK: - State
    
    /// Track failed prefetch URLs to avoid repeated attempts
    private var failedPrefetchUrls: Set<String> = []
    
    /// Last prefetch timestamp for debouncing
    private var lastPrefetchTime: Date = .distantPast
    
    // MARK: - Dependencies
    
    private let performanceMonitor: FeedPerformanceMonitor
    
    // MARK: - Init
    
    init(performanceMonitor: FeedPerformanceMonitor = .shared) {
        self.performanceMonitor = performanceMonitor
    }
    
    // MARK: - Prefetch Methods
    
    /// Prefetch images for upcoming posts to improve scroll performance
    /// - Parameters:
    ///   - posts: Array of posts to prefetch images from
    ///   - startIndex: Starting index in the posts array
    ///   - count: Number of posts to prefetch (default: 5)
    func prefetchImagesForPosts(_ posts: [FeedPost], startIndex: Int = 0, count: Int = 5) {
        let endIndex = min(startIndex + count, posts.count)
        guard startIndex < endIndex else { return }
        
        let upcomingPosts = posts[startIndex..<endIndex]
        let urls = upcomingPosts.flatMap { $0.displayMediaUrls }
            .filter { !failedPrefetchUrls.contains($0) }
        
        guard !urls.isEmpty else { return }
        
        // Start tracking image prefetch
        let signpostID = performanceMonitor.beginImagePrefetch(urlCount: urls.count)
        
        // Run prefetch asynchronously with low priority
        Task(priority: .utility) { [urls, prefetchTargetSize, weak self] in
            var successCount = 0
            let failCount = 0
            
            await ImageCacheService.shared.prefetch(
                urls: urls,
                targetSize: prefetchTargetSize,
                priority: .low
            )
            successCount = urls.count
            
            // Track prefetch completion
            self?.performanceMonitor.endImagePrefetch(
                signpostID: signpostID,
                successCount: successCount,
                failCount: failCount
            )
        }
    }
    
    /// Called when a post appears on screen - prefetch next batch
    /// - Parameters:
    ///   - index: The index of the post that appeared
    ///   - posts: All posts in the feed
    func onPostAppear(at index: Int, posts: [FeedPost]) {
        // Prefetch images for the next 5 posts
        prefetchImagesForPosts(posts, startIndex: index + 1, count: 5)
    }
    
    /// Smart prefetch with visibility tracking for optimal performance
    /// Uses debouncing to prevent excessive prefetch calls during rapid scrolling
    /// - Parameters:
    ///   - visibleIndices: Set of currently visible post indices
    ///   - posts: All posts in the feed
    func onVisiblePostsChanged(visibleIndices: Set<Int>, posts: [FeedPost]) {
        guard !posts.isEmpty else { return }
        
        // Debounce: skip if called too frequently (within 0.5 seconds)
        let now = Date()
        guard now.timeIntervalSince(lastPrefetchTime) > prefetchDebounceInterval else {
            return
        }
        lastPrefetchTime = now
        
        let sortedIndices = visibleIndices.sorted()
        guard let _ = sortedIndices.first,
              let lastVisible = sortedIndices.last else { return }
        
        // Get URLs for currently visible posts (high priority)
        let visibleUrls = sortedIndices
            .filter { $0 < posts.count }
            .flatMap { posts[$0].displayMediaUrls }
            .filter { !failedPrefetchUrls.contains($0) }
        
        // Get URLs for upcoming posts (prefetch with low priority)
        let prefetchStart = lastVisible + 1
        let prefetchEnd = min(prefetchStart + 8, posts.count)
        let upcomingUrls = (prefetchStart..<prefetchEnd)
            .flatMap { posts[$0].displayMediaUrls }
            .filter { !failedPrefetchUrls.contains($0) }
        
        // Use smart prefetch for optimal loading
        Task(priority: .utility) { [visibleUrls, upcomingUrls, prefetchTargetSize] in
            await ImageCacheService.shared.smartPrefetch(
                visibleUrls: visibleUrls,
                upcomingUrls: upcomingUrls,
                targetSize: prefetchTargetSize
            )
        }
    }
    
    /// Clear failed prefetch cache (called on refresh)
    func clearPrefetchFailures() {
        failedPrefetchUrls.removeAll()
    }
    
    /// Mark a URL as failed (for retry limiting)
    func markUrlAsFailed(_ url: String) {
        failedPrefetchUrls.insert(url)
    }
    
    /// Check if a URL has failed prefetching
    func hasFailedPrefetch(url: String) -> Bool {
        failedPrefetchUrls.contains(url)
    }
}
