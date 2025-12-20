import Foundation
import os.log

private let feedCacheLogger = Logger(subsystem: "com.app.icered", category: "FeedCache")

// MARK: - Cached Feed Response Wrapper

/// Wrapper for cached feed response with timestamp
final class CachedFeedResponse: NSObject {
    let response: FeedResponse
    let timestamp: Date
    let algorithm: FeedAlgorithm
    let channelId: String?

    init(response: FeedResponse, algorithm: FeedAlgorithm, channelId: String?) {
        self.response = response
        self.timestamp = Date()
        self.algorithm = algorithm
        self.channelId = channelId
        super.init()
    }

    /// Check if cache is expired
    func isExpired(maxAge: TimeInterval) -> Bool {
        return Date().timeIntervalSince(timestamp) > maxAge
    }
}

// MARK: - Disk Cache Entry (Codable)

private struct DiskCacheEntry: Codable {
    let response: FeedResponse
    let timestamp: Date
    let algorithm: String
    let channelId: String?
}

// MARK: - Feed Cache Service

/// Two-layer caching service for feed data (memory + disk)
actor FeedCacheService {
    static let shared = FeedCacheService()

    // MARK: - Cache Configuration

    private let memoryCache = NSCache<NSString, CachedFeedResponse>()
    private let fileManager = FileManager.default
    private var cacheDirectory: URL?

    // Cache expiration settings
    private let memoryCacheExpiration: TimeInterval = 3600      // 1 hour
    private let diskCacheExpiration: TimeInterval = 86400       // 24 hours
    private let maxMemoryCacheItems = 10

    // MARK: - Initialization

    private init() {
        // Configure memory cache
        memoryCache.countLimit = maxMemoryCacheItems

        // Setup disk cache directory
        if let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheDirectory = cachesDir.appendingPathComponent("FeedCache", isDirectory: true)
            try? fileManager.createDirectory(at: cacheDirectory!, withIntermediateDirectories: true)
        }

        // Start background cleanup
        Task.detached(priority: .background) { [weak self] in
            // Initial cleanup after 60 seconds
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            await self?.cleanupExpiredDiskCache()

            // Periodic cleanup every 6 hours
            while true {
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
                await self?.cleanupExpiredDiskCache()
            }
        }
    }

    // MARK: - Cache Key Generation

    private func cacheKey(algo: FeedAlgorithm, channelId: String?, cursor: String?) -> String {
        let algoKey = algo.rawValue
        let channelKey = channelId ?? "all"
        let cursorKey = cursor ?? "first"
        return "\(algoKey)_\(channelKey)_\(cursorKey)"
    }

    // MARK: - Memory Cache Operations

    /// Get cached feed from memory
    func getMemoryCachedFeed(
        algo: FeedAlgorithm,
        channelId: String?,
        cursor: String? = nil
    ) -> FeedResponse? {
        let key = cacheKey(algo: algo, channelId: channelId, cursor: cursor) as NSString

        guard let cached = memoryCache.object(forKey: key) else {
            return nil
        }

        // Check if expired
        if cached.isExpired(maxAge: memoryCacheExpiration) {
            memoryCache.removeObject(forKey: key)
            feedCacheLogger.debug("Memory cache expired for key: \(String(describing: key))")
            return nil
        }

        feedCacheLogger.debug("✅ Memory cache hit for key: \(String(describing: key))")
        return cached.response
    }

    /// Cache feed to memory
    func cacheToMemory(
        _ response: FeedResponse,
        algo: FeedAlgorithm,
        channelId: String?,
        cursor: String? = nil
    ) {
        let key = cacheKey(algo: algo, channelId: channelId, cursor: cursor) as NSString
        let cached = CachedFeedResponse(response: response, algorithm: algo, channelId: channelId)
        memoryCache.setObject(cached, forKey: key)
        feedCacheLogger.debug("Cached to memory: \(String(describing: key)) (\(response.posts.count) posts)")
    }

    // MARK: - Disk Cache Operations

    /// Get cached feed from disk
    func getDiskCachedFeed(
        algo: FeedAlgorithm,
        channelId: String?,
        cursor: String? = nil
    ) async -> FeedResponse? {
        guard let cacheDir = cacheDirectory else { return nil }

        let key = cacheKey(algo: algo, channelId: channelId, cursor: cursor)
        let fileURL = cacheDir.appendingPathComponent("\(key).json")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let entry = try JSONDecoder().decode(DiskCacheEntry.self, from: data)

            // Check if expired
            if Date().timeIntervalSince(entry.timestamp) > diskCacheExpiration {
                try? fileManager.removeItem(at: fileURL)
                feedCacheLogger.debug("Disk cache expired for key: \(key)")
                return nil
            }

            feedCacheLogger.debug("✅ Disk cache hit for key: \(key)")

            // Also populate memory cache
            let cached = CachedFeedResponse(
                response: entry.response,
                algorithm: algo,
                channelId: channelId
            )
            memoryCache.setObject(cached, forKey: key as NSString)

            return entry.response
        } catch {
            feedCacheLogger.error("Failed to load disk cache: \(error.localizedDescription)")
            return nil
        }
    }

    /// Cache feed to disk (async, non-blocking)
    func cacheToDisk(
        _ response: FeedResponse,
        algo: FeedAlgorithm,
        channelId: String?,
        cursor: String? = nil
    ) async {
        guard let cacheDir = cacheDirectory else { return }

        let key = cacheKey(algo: algo, channelId: channelId, cursor: cursor)
        let fileURL = cacheDir.appendingPathComponent("\(key).json")

        let entry = DiskCacheEntry(
            response: response,
            timestamp: Date(),
            algorithm: algo.rawValue,
            channelId: channelId
        )

        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: fileURL)
            feedCacheLogger.debug("Cached to disk: \(key) (\(response.posts.count) posts)")
        } catch {
            feedCacheLogger.error("Failed to cache to disk: \(error.localizedDescription)")
        }
    }

    // MARK: - Combined Cache Operations

    /// Get cached feed (checks memory first, then disk)
    func getCachedFeed(
        algo: FeedAlgorithm,
        channelId: String?,
        cursor: String? = nil
    ) async -> FeedResponse? {
        // Check memory cache first (fast)
        if let memoryCached = getMemoryCachedFeed(algo: algo, channelId: channelId, cursor: cursor) {
            return memoryCached
        }

        // Check disk cache (slower but persistent)
        return await getDiskCachedFeed(algo: algo, channelId: channelId, cursor: cursor)
    }

    /// Cache feed to both memory and disk
    func cacheFeed(
        _ response: FeedResponse,
        algo: FeedAlgorithm,
        channelId: String?,
        cursor: String? = nil
    ) async {
        // Cache to memory (synchronous)
        cacheToMemory(response, algo: algo, channelId: channelId, cursor: cursor)

        // Cache to disk (async, background)
        Task.detached(priority: .background) { [weak self] in
            await self?.cacheToDisk(response, algo: algo, channelId: channelId, cursor: cursor)
        }
    }

    // MARK: - Cache Invalidation

    /// Invalidate cache for a specific algorithm/channel
    func invalidateCache(for algo: FeedAlgorithm? = nil, channelId: String? = nil) async {
        // Clear memory cache
        if algo == nil && channelId == nil {
            memoryCache.removeAllObjects()
        }
        // Note: NSCache doesn't support partial removal, so we clear all for simplicity

        // Clear disk cache
        guard let cacheDir = cacheDirectory else { return }

        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)

            for file in files {
                let filename = file.lastPathComponent

                // If specific algo/channel, only remove matching files
                if let algo = algo {
                    if filename.hasPrefix(algo.rawValue) {
                        if let channelId = channelId {
                            if filename.contains("_\(channelId)_") {
                                try fileManager.removeItem(at: file)
                            }
                        } else {
                            try fileManager.removeItem(at: file)
                        }
                    }
                } else {
                    // Remove all
                    try fileManager.removeItem(at: file)
                }
            }

            feedCacheLogger.info("Cache invalidated")
        } catch {
            feedCacheLogger.error("Failed to invalidate cache: \(error.localizedDescription)")
        }
    }

    /// Invalidate cache when user creates new post
    /// This ensures the feed shows the new post after posting
    func invalidateCacheOnNewPost() async {
        // Clear memory cache completely for instant refresh
        memoryCache.removeAllObjects()

        // Clear disk cache for first page only (cursor = nil)
        // This implements stale-while-revalidate: we keep paginated caches but refresh the first page
        guard let cacheDir = cacheDirectory else { return }

        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)

            for file in files {
                let filename = file.lastPathComponent
                // Remove only first-page caches (containing "_first")
                if filename.contains("_first") {
                    try fileManager.removeItem(at: file)
                    feedCacheLogger.debug("Invalidated first-page cache: \(filename)")
                }
            }

            feedCacheLogger.info("Cache invalidated for new post")
        } catch {
            feedCacheLogger.error("Failed to invalidate cache on new post: \(error.localizedDescription)")
        }
    }

    /// Clear all caches
    func clearAllCache() async {
        memoryCache.removeAllObjects()

        guard let cacheDir = cacheDirectory else { return }

        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        feedCacheLogger.info("All feed cache cleared")
    }

    // MARK: - Cleanup

    /// Remove expired disk cache files
    private func cleanupExpiredDiskCache() async {
        guard let cacheDir = cacheDirectory else { return }

        let cutoffDate = Date().addingTimeInterval(-diskCacheExpiration)
        var removedCount = 0

        do {
            let files = try fileManager.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.creationDateKey]
            )

            for file in files {
                if let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   creationDate < cutoffDate {
                    try fileManager.removeItem(at: file)
                    removedCount += 1
                }
            }

            if removedCount > 0 {
                feedCacheLogger.info("Cleaned up \(removedCount) expired feed cache files")
            }
        } catch {
            feedCacheLogger.error("Failed to cleanup disk cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Cache Statistics

    /// Get cache statistics
    func getCacheStats() async -> (memoryItems: Int, diskFiles: Int, diskSize: Int64) {
        var diskFiles = 0
        var diskSize: Int64 = 0

        if let cacheDir = cacheDirectory,
           let enumerator = fileManager.enumerator(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let file as URL in enumerator {
                diskFiles += 1
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    diskSize += Int64(size)
                }
            }
        }

        return (
            memoryItems: memoryCache.countLimit, // Approximate, NSCache doesn't expose count
            diskFiles: diskFiles,
            diskSize: diskSize
        )
    }
}
