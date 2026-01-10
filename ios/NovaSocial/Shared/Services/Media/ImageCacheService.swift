import SwiftUI
import UIKit
import CommonCrypto
import os.log

private let imageLogger = Logger(subsystem: "com.app.icered", category: "ImageCache")

/// Priority level for image loading requests
enum ImageLoadPriority: Int, Comparable {
    case low = 0      // Prefetch, off-screen images
    case normal = 1   // Default priority
    case high = 2     // Currently visible images
    case immediate = 3 // User-initiated, blocking operations
    
    static func < (lhs: ImageLoadPriority, rhs: ImageLoadPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// A centralized image caching service with downsampling, prefetch, and priority queue
actor ImageCacheService {
    static let shared = ImageCacheService()

    // MARK: - Cache Configuration
    // NSCache is thread-safe, so we can use nonisolated(unsafe) to bypass Sendable checking
    nonisolated(unsafe) private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private var cacheDirectory: URL?
    private let session: URLSession

    // Configuration - dynamically sized based on device memory
    private let maxMemoryCacheSize: Int
    private let maxDiskCacheSize: Int = 500 * 1024 * 1024    // 500MB
    private let diskCacheExpiration: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    // Prefetch and priority queue
    private var prefetchTasks: [String: Task<UIImage?, Never>] = [:]
    private var pendingRequests: [String: (priority: ImageLoadPriority, task: Task<UIImage?, Never>)] = [:]
    private var activeTasks: Set<String> = []
    private let maxConcurrentLoads = 6

    // NotificationCenter observer reference for cleanup
    private var memoryWarningObserver: NSObjectProtocol?

    // Thumbnail cache for quick preview
    nonisolated(unsafe) private let thumbnailCache = NSCache<NSString, UIImage>()
    private let thumbnailSize = CGSize(width: 100, height: 100)

    // MARK: - Dynamic Cache Sizing

    /// Calculate optimal memory cache size based on device RAM
    private static func getOptimalMemoryCacheSize() -> Int {
        let totalMemory = ProcessInfo.processInfo.physicalMemory

        // Adaptive sizing based on device memory
        // < 2GB (older devices): 50MB
        // 2-4GB (iPhone 11, etc): 100MB
        // 4-6GB (iPhone 12-14): 150MB
        // > 6GB (iPhone 15 Pro, etc): 200MB
        if totalMemory < 2 * 1024 * 1024 * 1024 {
            return 50 * 1024 * 1024
        } else if totalMemory < 4 * 1024 * 1024 * 1024 {
            return 100 * 1024 * 1024
        } else if totalMemory < 6 * 1024 * 1024 * 1024 {
            return 150 * 1024 * 1024
        }
        return 200 * 1024 * 1024
    }

    /// Calculate actual memory cost for a UIImage (not compressed data size)
    private func calculateActualMemoryCost(for image: UIImage) -> Int {
        // UIImage memory = width * height * scale^2 * 4 bytes (RGBA)
        let pixelCount = Int(image.size.width * image.size.height * image.scale * image.scale)
        return pixelCount * 4
    }

    private init() {
        // Dynamic cache sizing based on device memory
        maxMemoryCacheSize = Self.getOptimalMemoryCacheSize()

        // Setup cache synchronously since these are non-isolated operations
        memoryCache.totalCostLimit = maxMemoryCacheSize

        // Dedicated URLSession for media fetching.
        // Avoids coupling image downloads to APIClient's URLSession config/caching.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Modern iOS uses HTTP/2 and HTTP/3 which handle connection multiplexing automatically
        config.httpMaximumConnectionsPerHost = 6
        config.allowsCellularAccess = true
        self.session = URLSession(configuration: config)

        // Setup disk cache directory
        if let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheDirectory = cachesDir.appendingPathComponent("ImageCache", isDirectory: true)
            try? fileManager.createDirectory(at: cacheDirectory!, withIntermediateDirectories: true)
        }

        // Setup memory warning observer (on main actor) - store reference for proper cleanup
        Task { @MainActor [weak self] in
            let observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task {
                    await self?.handleMemoryWarning()
                }
            }
            await self?.setMemoryWarningObserver(observer)
        }

        // Start background disk cache cleanup
        Task.detached(priority: .background) { [weak self] in
            // Initial cleanup after 30 seconds
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            await self?.performDiskCacheCleanup()

            // Periodic cleanup every hour
            while true {
                try? await Task.sleep(nanoseconds: 3600 * 1_000_000_000)
                await self?.performDiskCacheCleanup()
            }
        }
    }

    // MARK: - Memory Warning Handling

    /// Set the memory warning observer reference (called from Task)
    private func setMemoryWarningObserver(_ observer: NSObjectProtocol) {
        memoryWarningObserver = observer
    }

    /// Handle memory warning by clearing caches
    private func handleMemoryWarning() {
        imageLogger.warning("⚠️ Memory warning received - clearing image caches")
        memoryCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    /// Cleanup resources (for completeness, though singleton rarely deinits)
    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Disk Cache Cleanup

    /// Perform disk cache cleanup (removes expired and over-limit files)
    private func performDiskCacheCleanup() async {
        await cleanupExpiredDiskCache()
        await enforceDiskCacheLimit()
    }

    /// Remove disk cache files older than expiration period
    private func cleanupExpiredDiskCache() async {
        guard let cacheDir = cacheDirectory else { return }

        let cutoffDate = Date().addingTimeInterval(-diskCacheExpiration)
        var removedCount = 0

        if let enumerator = fileManager.enumerator(
            at: cacheDir,
            includingPropertiesForKeys: [.contentAccessDateKey, .creationDateKey]
        ) {
            for case let fileURL as URL in enumerator {
                if let accessDate = try? fileURL.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate,
                   accessDate < cutoffDate {
                    try? fileManager.removeItem(at: fileURL)
                    removedCount += 1
                }
            }
        }

        if removedCount > 0 {
            imageLogger.info("🗑️ Cleaned up \(removedCount) expired image cache files")
        }
    }

    /// Enforce disk cache size limit using LRU eviction
    private func enforceDiskCacheLimit() async {
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
            // Sort by access date (oldest first) for LRU eviction
            files.sort { $0.date < $1.date }

            var currentSize = totalSize
            let targetSize = Int64(maxDiskCacheSize * 3 / 4) // Reduce to 75% of max
            var removedCount = 0

            for file in files {
                if currentSize <= targetSize { break }

                try? fileManager.removeItem(at: file.url)
                currentSize -= file.size
                removedCount += 1
            }

            if removedCount > 0 {
                imageLogger.info("🗑️ LRU cleanup: removed \(removedCount) image cache files, freed \((totalSize - currentSize) / 1024)KB")
            }
        }
    }

    // MARK: - Public API

    /// Load an image with optional downsampling and priority
    /// Uses APIClient's session for connection pooling and HTTP caching benefits
    func loadImage(
        from urlString: String,
        targetSize: CGSize? = nil,
        scale: CGFloat? = nil,
        priority: ImageLoadPriority = .normal
    ) async -> UIImage? {
        let displayScale: CGFloat
        if let scale = scale {
            displayScale = scale
        } else {
            // Get scale from connected window scene (iOS 26+ compatible)
            displayScale = await MainActor.run {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.screen.scale ?? 3.0
            }
        }
        let cacheKey = cacheKey(for: urlString, targetSize: targetSize)

        // Check memory cache first (instant return)
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        // Check disk cache (fast local read)
        if let diskCached = await loadFromDisk(key: cacheKey) {
            let memoryCost = calculateActualMemoryCost(for: diskCached)
            memoryCache.setObject(diskCached, forKey: cacheKey as NSString, cost: memoryCost)
            return diskCached
        }

        // Download and process
        guard let url = URL(string: urlString) else { return nil }

        do {
            if url.isFileURL {
                let data = try Data(contentsOf: url)

                var image: UIImage?
                if let targetSize = targetSize {
                    image = downsample(data: data, to: targetSize, scale: displayScale)
                } else {
                    image = UIImage(data: data)
                }

                if let image = image {
                    let decodedImage: UIImage
                    if #available(iOS 15.0, *) {
                        decodedImage = await image.byPreparingForDisplay() ?? image
                    } else {
                        decodedImage = await forceDecodeImage(image) ?? image
                    }

                    let memoryCost = calculateActualMemoryCost(for: decodedImage)
                    memoryCache.setObject(decodedImage, forKey: cacheKey as NSString, cost: memoryCost)
                    return decodedImage
                }

                return nil
            }

            // Configure request with priority
            var request = URLRequest(url: url)
            request.networkServiceType = priority == .immediate ? .responsiveData : .default
            request.timeoutInterval = priority == .immediate ? 30 : 60
            
            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                // Accept 200-299 and cache revalidation 304.
                if !(200...299).contains(httpResponse.statusCode) && httpResponse.statusCode != 304 {
                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                    imageLogger.error("❌ Image request failed: \(urlString, privacy: .public) status=\(httpResponse.statusCode) contentType=\(contentType, privacy: .public) bytes=\(data.count)")
                    #if DEBUG
                    if let bodyPreview = String(data: data.prefix(256), encoding: .utf8), !bodyPreview.isEmpty {
                        imageLogger.debug("Body preview: \(bodyPreview, privacy: .public)")
                    }
                    #endif
                    return nil
                }
            }

            var image: UIImage?
            if let targetSize = targetSize {
                image = downsample(data: data, to: targetSize, scale: displayScale)
            } else {
                image = UIImage(data: data)
            }

            if image == nil {
                #if DEBUG
                let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                imageLogger.error("❌ Failed to decode image data: \(urlString, privacy: .public) contentType=\(contentType, privacy: .public) bytes=\(data.count)")
                if let bodyPreview = String(data: data.prefix(256), encoding: .utf8), !bodyPreview.isEmpty {
                    imageLogger.debug("Body preview: \(bodyPreview, privacy: .public)")
                }
                #endif
            }

            if let image = image {
                // 🚀 性能優化：預解碼圖片避免主線程解碼造成卡頓
                // UIImage 是惰性解碼的，首次渲染時會在主線程解碼導致掉幀
                // prepareForDisplay() 會在背景線程完成解碼
                let decodedImage: UIImage
                if #available(iOS 15.0, *) {
                    decodedImage = await image.byPreparingForDisplay() ?? image
                } else {
                    // iOS 14 fallback: 手動強制解碼
                    decodedImage = await forceDecodeImage(image) ?? image
                }
                
                // Cache to memory with actual memory cost (not compressed data size)
                let memoryCost = calculateActualMemoryCost(for: decodedImage)
                memoryCache.setObject(decodedImage, forKey: cacheKey as NSString, cost: memoryCost)
                // Cache to disk asynchronously (don't block return)
                Task.detached(priority: .background) { [weak self] in
                    await self?.saveToDisk(image: decodedImage, key: cacheKey)
                }
                
                // Also create and cache thumbnail for quick previews
                if targetSize == nil || (targetSize!.width > thumbnailSize.width * 2) {
                    Task.detached(priority: .background) { [weak self] in
                        await self?.createAndCacheThumbnail(from: data, urlString: urlString, scale: displayScale)
                    }
                }
                
                return decodedImage
            }

            return image
        } catch {
            imageLogger.error("❌ Failed to load image from URL: \(urlString)")
            imageLogger.error("Error: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                imageLogger.error("URLError code: \(urlError.code.rawValue)")
            }
            return nil
        }
    }
    
    /// Load thumbnail quickly for preview while full image loads
    /// Returns cached thumbnail immediately if available
    func loadThumbnail(from urlString: String) async -> UIImage? {
        let thumbnailKey = "thumb_\(urlString)" as NSString
        
        // Check thumbnail cache
        if let cached = thumbnailCache.object(forKey: thumbnailKey) {
            return cached
        }
        
        // Check if we have the full image cached (use that instead)
        let fullCacheKey = cacheKey(for: urlString, targetSize: nil)
        if let fullImage = memoryCache.object(forKey: fullCacheKey as NSString) {
            // Create thumbnail from full image
            let thumbnail = await createThumbnail(from: fullImage)
            if let thumbnail = thumbnail {
                thumbnailCache.setObject(thumbnail, forKey: thumbnailKey)
            }
            return thumbnail
        }
        
        // Load thumbnail from disk if exists
        if let diskThumbnail = await loadFromDisk(key: String(thumbnailKey)) {
            thumbnailCache.setObject(diskThumbnail, forKey: thumbnailKey)
            return diskThumbnail
        }
        
        return nil
    }
    
    /// Load image with thumbnail fallback for progressive loading
    /// Returns thumbnail immediately while loading full image in background
    func loadImageProgressive(
        from urlString: String,
        targetSize: CGSize? = nil,
        scale: CGFloat? = nil,
        onThumbnailLoaded: ((UIImage) -> Void)? = nil,
        onFullImageLoaded: ((UIImage) -> Void)? = nil
    ) async -> UIImage? {
        // Try to return thumbnail immediately
        if let thumbnail = await loadThumbnail(from: urlString) {
            await MainActor.run {
                onThumbnailLoaded?(thumbnail)
            }
        }
        
        // Load full image
        let fullImage = await loadImage(from: urlString, targetSize: targetSize, scale: scale, priority: .high)
        
        if let fullImage = fullImage {
            await MainActor.run {
                onFullImageLoaded?(fullImage)
            }
        }
        
        return fullImage
    }

    /// Prefetch images for upcoming cells
    func prefetch(urls: [String], targetSize: CGSize? = nil, priority: ImageLoadPriority = .low) {
        for urlString in urls {
            let cacheKey = cacheKey(for: urlString, targetSize: targetSize)

            // Skip if already cached or being fetched
            if memoryCache.object(forKey: cacheKey as NSString) != nil { continue }
            if prefetchTasks[cacheKey] != nil { continue }

            prefetchTasks[cacheKey] = Task(priority: priority == .low ? .background : .medium) {
                let image = await loadImage(from: urlString, targetSize: targetSize, priority: priority)
                prefetchTasks.removeValue(forKey: cacheKey)
                return image
            }
        }
    }

    /// Cancel prefetch for URLs that are no longer needed
    func cancelPrefetch(urls: [String], targetSize: CGSize? = nil) {
        for urlString in urls {
            let cacheKey = cacheKey(for: urlString, targetSize: targetSize)
            prefetchTasks[cacheKey]?.cancel()
            prefetchTasks.removeValue(forKey: cacheKey)
        }
    }

    /// Clear all caches
    func clearCache() async {
        memoryCache.removeAllObjects()
        if let cacheDir = cacheDirectory {
            try? fileManager.removeItem(at: cacheDir)
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }

    /// Evict specific URLs from memory cache (keeps disk cache intact)
    /// Used to free memory for off-screen images while preserving quick reload capability
    func evictFromMemory(urls: [String]) {
        for urlString in urls {
            // Remove all size variants for this URL
            let baseKey = cacheKey(for: urlString, targetSize: nil)
            memoryCache.removeObject(forKey: baseKey as NSString)

            // Also remove thumbnail if exists
            let thumbnailKey = "thumb_\(urlString)" as NSString
            thumbnailCache.removeObject(forKey: thumbnailKey)
        }
    }

    /// Prefetch images with smart prioritization based on visibility
    /// - Parameters:
    ///   - visibleUrls: URLs currently visible on screen (high priority)
    ///   - upcomingUrls: URLs that will be visible soon (normal priority)
    ///   - targetSize: Target size for downsampling
    func smartPrefetch(
        visibleUrls: [String],
        upcomingUrls: [String],
        targetSize: CGSize? = nil
    ) {
        // Cancel any prefetch tasks for URLs no longer relevant
        let allRelevantUrls = Set(visibleUrls + upcomingUrls)
        let currentTasks = Set(prefetchTasks.keys)
        let tasksToCancel = currentTasks.subtracting(allRelevantUrls.map { cacheKey(for: $0, targetSize: targetSize) })
        
        for key in tasksToCancel {
            prefetchTasks[key]?.cancel()
            prefetchTasks.removeValue(forKey: key)
        }
        
        // Prefetch visible URLs with high priority
        prefetch(urls: visibleUrls, targetSize: targetSize, priority: .high)
        
        // Prefetch upcoming URLs with low priority
        prefetch(urls: upcomingUrls, targetSize: targetSize, priority: .low)
    }
    
    /// Get cache statistics for debugging
    func getCacheStats() -> (memoryCount: Int, diskCount: Int, prefetchActive: Int) {
        var diskCount = 0
        if let cacheDir = cacheDirectory {
            diskCount = (try? fileManager.contentsOfDirectory(atPath: cacheDir.path).count) ?? 0
        }
        return (
            memoryCount: memoryCache.totalCostLimit > 0 ? 1 : 0, // NSCache doesn't expose count
            diskCount: diskCount,
            prefetchActive: prefetchTasks.count
        )
    }

    /// Pre-cache an image with a URL key
    /// Used to cache locally-created images (e.g., uploaded images) with their CDN URLs
    /// This ensures the image is immediately available when the feed tries to display it,
    /// avoiding CDN propagation delay issues
    func preCacheImage(_ image: UIImage, for urlString: String, targetSize: CGSize? = nil) {
        let key = cacheKey(for: urlString, targetSize: targetSize)
        let memoryCost = calculateActualMemoryCost(for: image)
        memoryCache.setObject(image, forKey: key as NSString, cost: memoryCost)

        // Also save to disk for persistence
        Task.detached(priority: .background) { [weak self] in
            await self?.saveToDisk(image: image, key: key)
        }

        // Create and cache thumbnail as well
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            if let thumbnail = await self.createThumbnail(from: image) {
                let thumbnailKey = "thumb_\(urlString)" as NSString
                self.thumbnailCache.setObject(thumbnail, forKey: thumbnailKey)
            }
        }

        #if DEBUG
        imageLogger.info("📦 Pre-cached image for URL: \(urlString.suffix(50))")
        #endif
    }

    // MARK: - Private Helpers

    private func cacheKey(for urlString: String, targetSize: CGSize?) -> String {
        if let size = targetSize {
            return "\(urlString)_\(Int(size.width))x\(Int(size.height))"
        }
        return urlString
    }

    private func createAndCacheThumbnail(from data: Data, urlString: String, scale: CGFloat) async {
        guard let thumbnail = downsample(data: data, to: thumbnailSize, scale: scale) else { return }
        let thumbnailKey = "thumb_\(urlString)" as NSString
        thumbnailCache.setObject(thumbnail, forKey: thumbnailKey)
        await saveToDisk(image: thumbnail, key: String(thumbnailKey))
    }
    
    private func createThumbnail(from image: UIImage) async -> UIImage? {
        // Get scale from connected window scene (iOS 26+ compatible)
        let scale = await MainActor.run {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.screen.scale ?? 3.0
        }
        let size = CGSize(
            width: thumbnailSize.width * scale,
            height: thumbnailSize.height * scale
        )
        
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func downsample(data: Data, to targetSize: CGSize, scale: CGFloat) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else { return nil }

        let maxDimensionInPixels = max(targetSize.width, targetSize.height) * scale
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else { return nil }
        return UIImage(cgImage: downsampledImage)
    }

    private func loadFromDisk(key: String) async -> UIImage? {
        guard let cacheDir = cacheDirectory else { return nil }
        let fileURL = cacheDir.appendingPathComponent(key.sha256Hash)

        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }

        // 🚀 性能優化：從磁盤載入後也要預解碼
        if #available(iOS 15.0, *) {
            return await image.byPreparingForDisplay() ?? image
        } else {
            return await forceDecodeImage(image) ?? image
        }
    }
    
    /// iOS 14 fallback: 手動強制解碼圖片
    private func forceDecodeImage(_ image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return image }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // 創建位圖上下文強制解碼
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return image
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let decodedCGImage = context.makeImage() else {
            return image
        }
        
        return UIImage(cgImage: decodedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private func saveToDisk(image: UIImage, key: String) async {
        guard let cacheDir = cacheDirectory,
              let data = image.jpegData(compressionQuality: 0.8) else { return }

        let fileURL = cacheDir.appendingPathComponent(key.sha256Hash)
        try? data.write(to: fileURL)
    }
}

// MARK: - String Extension for Hashing
private extension String {
    var sha256Hash: String {
        let data = Data(self.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// NOTE: VideoCacheService has been moved to VideoCacheService.swift
