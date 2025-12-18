import SwiftUI
import UIKit
import CommonCrypto

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
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private var cacheDirectory: URL?

    // Configuration
    private let maxMemoryCacheSize: Int = 150 * 1024 * 1024  // 150MB (increased for better performance)
    private let maxDiskCacheSize: Int = 500 * 1024 * 1024    // 500MB

    // Prefetch and priority queue
    private var prefetchTasks: [String: Task<UIImage?, Never>] = [:]
    private var pendingRequests: [String: (priority: ImageLoadPriority, task: Task<UIImage?, Never>)] = [:]
    private var activeTasks: Set<String> = []
    private let maxConcurrentLoads = 6
    
    // Thumbnail cache for quick preview
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let thumbnailSize = CGSize(width: 100, height: 100)

    private init() {
        // Setup cache synchronously since these are non-isolated operations
        memoryCache.totalCostLimit = maxMemoryCacheSize

        // Setup disk cache directory
        if let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheDirectory = cachesDir.appendingPathComponent("ImageCache", isDirectory: true)
            try? fileManager.createDirectory(at: cacheDirectory!, withIntermediateDirectories: true)
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
            displayScale = await MainActor.run { UIScreen.main.scale }
        }
        let cacheKey = cacheKey(for: urlString, targetSize: targetSize)

        // Check memory cache first (instant return)
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        // Check disk cache (fast local read)
        if let diskCached = await loadFromDisk(key: cacheKey) {
            memoryCache.setObject(diskCached, forKey: cacheKey as NSString, cost: diskCached.jpegData(compressionQuality: 1)?.count ?? 0)
            return diskCached
        }

        // Download and process
        guard let url = URL(string: urlString) else { return nil }

        do {
            // Configure request with priority
            var request = URLRequest(url: url)
            request.networkServiceType = priority == .immediate ? .responsiveData : .default
            
            // Use APIClient's session for HTTP/2 connection pooling and caching
            let (data, _) = try await APIClient.shared.session.data(for: request)

            var image: UIImage?
            if let targetSize = targetSize {
                image = downsample(data: data, to: targetSize, scale: displayScale)
            } else {
                image = UIImage(data: data)
            }

            if let image = image {
                // Cache to memory
                memoryCache.setObject(image, forKey: cacheKey as NSString, cost: data.count)
                // Cache to disk asynchronously (don't block return)
                Task.detached(priority: .background) { [weak self] in
                    await self?.saveToDisk(image: image, key: cacheKey)
                }
                
                // Also create and cache thumbnail for quick previews
                if targetSize == nil || (targetSize!.width > thumbnailSize.width * 2) {
                    Task.detached(priority: .background) { [weak self] in
                        await self?.createAndCacheThumbnail(from: data, urlString: urlString, scale: displayScale)
                    }
                }
            }

            return image
        } catch {
            #if DEBUG
            print("[ImageCache] Failed to load image: \(error.localizedDescription)")
            #endif
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
        let scale = await MainActor.run { UIScreen.main.scale }
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
              let data = try? Data(contentsOf: fileURL) else { return nil }

        return UIImage(data: data)
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
