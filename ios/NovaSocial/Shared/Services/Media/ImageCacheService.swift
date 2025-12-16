import SwiftUI
import UIKit
import CommonCrypto

/// A centralized image caching service with downsampling and prefetch capabilities
actor ImageCacheService {
    static let shared = ImageCacheService()

    // MARK: - Cache Configuration
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private var cacheDirectory: URL?

    // Configuration
    private let maxMemoryCacheSize: Int = 100 * 1024 * 1024  // 100MB
    private let maxDiskCacheSize: Int = 500 * 1024 * 1024    // 500MB

    // Prefetch queue
    private var prefetchTasks: [String: Task<UIImage?, Never>] = [:]

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

    /// Load an image with optional downsampling
    /// Uses APIClient's session for connection pooling and HTTP caching benefits
    func loadImage(
        from urlString: String,
        targetSize: CGSize? = nil,
        scale: CGFloat? = nil
    ) async -> UIImage? {
        let displayScale: CGFloat
        if let scale = scale {
            displayScale = scale
        } else {
            displayScale = await MainActor.run { UIScreen.main.scale }
        }
        let cacheKey = cacheKey(for: urlString, targetSize: targetSize)

        // Check memory cache
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        // Check disk cache
        if let diskCached = await loadFromDisk(key: cacheKey) {
            memoryCache.setObject(diskCached, forKey: cacheKey as NSString, cost: diskCached.jpegData(compressionQuality: 1)?.count ?? 0)
            return diskCached
        }

        // Download and process
        guard let url = URL(string: urlString) else { return nil }

        do {
            // Use APIClient's session for HTTP/2 connection pooling and caching
            let (data, _) = try await APIClient.shared.session.data(from: url)

            var image: UIImage?
            if let targetSize = targetSize {
                image = downsample(data: data, to: targetSize, scale: displayScale)
            } else {
                image = UIImage(data: data)
            }

            if let image = image {
                // Cache to memory
                memoryCache.setObject(image, forKey: cacheKey as NSString, cost: data.count)
                // Cache to disk
                await saveToDisk(image: image, key: cacheKey)
            }

            return image
        } catch {
            return nil
        }
    }

    /// Prefetch images for upcoming cells
    func prefetch(urls: [String], targetSize: CGSize? = nil) {
        for urlString in urls {
            let cacheKey = cacheKey(for: urlString, targetSize: targetSize)

            // Skip if already cached or being fetched
            if memoryCache.object(forKey: cacheKey as NSString) != nil { continue }
            if prefetchTasks[cacheKey] != nil { continue }

            prefetchTasks[cacheKey] = Task {
                let image = await loadImage(from: urlString, targetSize: targetSize)
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

    // MARK: - Private Helpers

    private func cacheKey(for urlString: String, targetSize: CGSize?) -> String {
        if let size = targetSize {
            return "\(urlString)_\(Int(size.width))x\(Int(size.height))"
        }
        return urlString
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
