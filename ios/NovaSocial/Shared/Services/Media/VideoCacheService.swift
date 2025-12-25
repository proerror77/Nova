import Foundation
import CommonCrypto
import os.log

private let videoLogger = Logger(subsystem: "com.app.icered", category: "VideoCache")

/// Priority levels for video loading
enum VideoLoadPriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case immediate = 3

    static func < (lhs: VideoLoadPriority, rhs: VideoLoadPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var taskPriority: TaskPriority {
        switch self {
        case .low: return .background
        case .normal: return .medium
        case .high: return .high
        case .immediate: return .userInitiated
        }
    }
}

/// Result of video cache lookup
enum VideoCacheResult {
    case cached(URL)      // Local file URL
    case downloading      // Download in progress
    case notCached        // Not in cache
}

/// Video caching service - downloads and caches videos for faster playback
actor VideoCacheService {
    static let shared = VideoCacheService()

    // MARK: - Cache Configuration
    private let fileManager = FileManager.default
    private var cacheDirectory: URL?

    // Configuration - video cache can be larger since videos are larger files
    private let maxDiskCacheSize: Int = 1024 * 1024 * 1024  // 1GB max cache
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    // Active downloads tracking
    private var activeDownloads: [String: Task<URL?, Never>] = [:]
    private var downloadProgress: [String: Double] = [:]

    // In-memory URL cache for quick lookups
    private var urlCache: [String: URL] = [:]

    private init() {
        // Setup disk cache directory
        if let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheDirectory = cachesDir.appendingPathComponent("VideoCache", isDirectory: true)
            try? fileManager.createDirectory(at: cacheDirectory!, withIntermediateDirectories: true)
        }

        // Schedule periodic cache cleanup
        Task.detached(priority: .background) { [weak self] in
            await self?.cleanupOldCacheFiles()
        }
    }

    // MARK: - Public API

    /// Check if a video is cached and return its local URL
    func getCachedVideoURL(for urlString: String) -> URL? {
        let cacheKey = videoCacheKey(for: urlString)

        // Check in-memory URL cache first
        if let cached = urlCache[cacheKey] {
            if fileManager.fileExists(atPath: cached.path) {
                return cached
            } else {
                // File was deleted, remove from cache
                urlCache.removeValue(forKey: cacheKey)
            }
        }

        // Check disk
        guard let cacheDir = cacheDirectory else { return nil }
        let fileURL = cacheDir.appendingPathComponent(cacheKey)

        if fileManager.fileExists(atPath: fileURL.path) {
            urlCache[cacheKey] = fileURL
            return fileURL
        }

        return nil
    }

    /// Get video URL - returns cached URL if available, otherwise downloads and caches
    /// Returns the local file URL when ready
    func getVideoURL(
        for urlString: String,
        priority: VideoLoadPriority = .normal
    ) async -> URL? {
        // Check cache first
        if let cachedURL = getCachedVideoURL(for: urlString) {
            videoLogger.info("✅ Video cache hit: \(urlString.suffix(30))")
            return cachedURL
        }

        // Check if download is already in progress
        let cacheKey = videoCacheKey(for: urlString)
        if let existingTask = activeDownloads[cacheKey] {
            videoLogger.info("⏳ Video download in progress, waiting: \(urlString.suffix(30))")
            return await existingTask.value
        }

        // Start download
        videoLogger.info("📥 Starting video download: \(urlString.suffix(30))")
        let downloadTask = Task<URL?, Never>(priority: priority.taskPriority) {
            await self.downloadAndCacheVideo(urlString: urlString)
        }

        activeDownloads[cacheKey] = downloadTask
        let result = await downloadTask.value
        activeDownloads.removeValue(forKey: cacheKey)

        return result
    }

    /// Start prefetching a video in the background
    func prefetchVideo(urlString: String, priority: VideoLoadPriority = .low) {
        let cacheKey = videoCacheKey(for: urlString)

        // Skip if already cached or downloading
        if getCachedVideoURL(for: urlString) != nil { return }
        if activeDownloads[cacheKey] != nil { return }

        videoLogger.info("📦 Prefetching video: \(urlString.suffix(30))")

        let downloadTask = Task<URL?, Never>(priority: priority.taskPriority) {
            await self.downloadAndCacheVideo(urlString: urlString)
        }

        activeDownloads[cacheKey] = downloadTask

        // Fire and forget - don't await
        Task.detached(priority: .background) {
            _ = await downloadTask.value
            await self.removeActiveDownload(for: cacheKey)
        }
    }

    /// Cancel prefetch for a URL
    func cancelPrefetch(urlString: String) {
        let cacheKey = videoCacheKey(for: urlString)
        activeDownloads[cacheKey]?.cancel()
        activeDownloads.removeValue(forKey: cacheKey)
    }

    /// Get download progress for a URL (0.0 to 1.0)
    func getDownloadProgress(for urlString: String) -> Double {
        let cacheKey = videoCacheKey(for: urlString)
        return downloadProgress[cacheKey] ?? 0.0
    }

    /// Check the cache status for a video URL
    func getCacheStatus(for urlString: String) -> VideoCacheResult {
        if let cached = getCachedVideoURL(for: urlString) {
            return .cached(cached)
        }

        let cacheKey = videoCacheKey(for: urlString)
        if activeDownloads[cacheKey] != nil {
            return .downloading
        }

        return .notCached
    }

    /// Clear all cached videos
    func clearCache() async {
        // Cancel all active downloads
        for task in activeDownloads.values {
            task.cancel()
        }
        activeDownloads.removeAll()
        downloadProgress.removeAll()
        urlCache.removeAll()

        // Delete cache directory contents
        if let cacheDir = cacheDirectory {
            try? fileManager.removeItem(at: cacheDir)
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }

        videoLogger.info("🗑️ Video cache cleared")
    }

    /// Get cache statistics
    func getCacheStats() -> (fileCount: Int, totalSize: Int64) {
        guard let cacheDir = cacheDirectory else { return (0, 0) }

        var fileCount = 0
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                fileCount += 1
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return (fileCount, totalSize)
    }

    // MARK: - Private Helpers

    private func removeActiveDownload(for key: String) {
        activeDownloads.removeValue(forKey: key)
        downloadProgress.removeValue(forKey: key)
    }

    private func videoCacheKey(for urlString: String) -> String {
        // Use SHA256 hash of URL as filename
        let data = Data(urlString.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        let hashString = hash.map { String(format: "%02x", $0) }.joined()

        // Preserve file extension for proper playback
        let ext = (urlString as NSString).pathExtension.lowercased()
        let validExtension = ["mp4", "mov", "m4v", "webm"].contains(ext) ? ext : "mp4"

        return "\(hashString).\(validExtension)"
    }

    private func downloadAndCacheVideo(urlString: String) async -> URL? {
        guard let url = URL(string: urlString),
              let cacheDir = cacheDirectory else {
            return nil
        }

        let cacheKey = videoCacheKey(for: urlString)
        let destinationURL = cacheDir.appendingPathComponent(cacheKey)

        do {
            // Create a download request
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (tempURL, response) = try await URLSession.shared.download(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                videoLogger.error("❌ Video download failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }

            // Move to cache directory
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.moveItem(at: tempURL, to: destinationURL)

            // Update in-memory cache
            urlCache[cacheKey] = destinationURL

            // Get file size for logging
            let fileSize = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
            videoLogger.info("✅ Video cached: \(urlString.suffix(30)) (\(fileSize / 1024)KB)")

            // Check and cleanup cache if needed
            Task.detached(priority: .background) { [weak self] in
                await self?.enforceCacheSizeLimit()
            }

            return destinationURL
        } catch {
            videoLogger.error("❌ Video download error: \(error.localizedDescription)")
            return nil
        }
    }

    private func cleanupOldCacheFiles() async {
        guard let cacheDir = cacheDirectory else { return }

        let cutoffDate = Date().addingTimeInterval(-maxCacheAge)

        if let enumerator = fileManager.enumerator(
            at: cacheDir,
            includingPropertiesForKeys: [.contentAccessDateKey, .creationDateKey]
        ) {
            for case let fileURL as URL in enumerator {
                if let accessDate = try? fileURL.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate,
                   accessDate < cutoffDate {
                    try? fileManager.removeItem(at: fileURL)
                    videoLogger.info("🗑️ Removed old cached video: \(fileURL.lastPathComponent)")
                }
            }
        }
    }

    private func enforceCacheSizeLimit() async {
        guard let cacheDir = cacheDirectory else { return }

        var files: [(url: URL, date: Date, size: Int64)] = []

        if let enumerator = fileManager.enumerator(
            at: cacheDir,
            includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey]
        ) {
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.contentAccessDateKey, .fileSizeKey])
                let date = values?.contentAccessDate ?? Date.distantPast
                let size = Int64(values?.fileSize ?? 0)
                files.append((url: fileURL, date: date, size: size))
            }
        }

        // Calculate total size
        let totalSize = files.reduce(0) { $0 + $1.size }

        if totalSize > maxDiskCacheSize {
            // Sort by access date (oldest first)
            files.sort { $0.date < $1.date }

            var currentSize = totalSize
            let targetSize = maxDiskCacheSize * 3 / 4 // Reduce to 75% of max

            for file in files {
                if currentSize <= targetSize { break }

                try? fileManager.removeItem(at: file.url)
                urlCache.removeValue(forKey: file.url.lastPathComponent)
                currentSize -= file.size
                videoLogger.info("🗑️ Cache cleanup: removed \(file.url.lastPathComponent)")
            }
        }
    }
}
