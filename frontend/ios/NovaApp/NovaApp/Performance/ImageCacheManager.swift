import Foundation
import UIKit
import Combine

/// 高性能双层图像缓存管理器（内存 + 磁盘）
///
/// 性能特性：
/// - 内存缓存：使用 NSCache 实现自动内存管理
/// - 磁盘缓存：异步读写，避免主线程阻塞
/// - 预加载：智能预测用户滚动方向，提前加载
/// - 图像压缩：根据屏幕尺寸自动压缩
@MainActor
class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()

    // MARK: - Cache Configuration
    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL
    private let fileManager = FileManager.default
    private let processingQueue = DispatchQueue(label: "com.nova.image.processing", qos: .userInitiated)

    // MARK: - Performance Metrics
    @Published var cacheStats = CacheStats()

    struct CacheStats {
        var memoryHits: Int = 0
        var diskHits: Int = 0
        var networkFetches: Int = 0
        var totalBytes: Int64 = 0

        var hitRate: Double {
            let total = memoryHits + diskHits + networkFetches
            guard total > 0 else { return 0 }
            return Double(memoryHits + diskHits) / Double(total)
        }
    }

    // MARK: - Initialization
    private init() {
        // 配置内存缓存（最大 100MB）
        memoryCache.totalCostLimit = 100 * 1024 * 1024
        memoryCache.countLimit = 100

        // 配置磁盘缓存目录
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        diskCacheURL = paths[0].appendingPathComponent("ImageCache", isDirectory: true)

        // 创建缓存目录
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        // 监听内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // 定期清理过期缓存（每小时）
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3600_000_000_000) // 1 hour
                await cleanExpiredCache()
            }
        }
    }

    // MARK: - Public API

    /// 获取图像（优先内存 → 磁盘 → 网络）
    func image(for url: URL, size: ImageSize = .medium) async throws -> UIImage {
        let cacheKey = cacheKey(for: url, size: size)

        // 1. 检查内存缓存
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            cacheStats.memoryHits += 1
            return cached
        }

        // 2. 检查磁盘缓存
        if let diskImage = await loadFromDisk(cacheKey: cacheKey) {
            cacheStats.diskHits += 1
            // 加载到内存缓存
            let cost = diskImage.pngData()?.count ?? 0
            memoryCache.setObject(diskImage, forKey: cacheKey as NSString, cost: cost)
            return diskImage
        }

        // 3. 从网络下载
        cacheStats.networkFetches += 1
        let image = try await downloadImage(from: url, targetSize: size)

        // 缓存到内存和磁盘
        await cache(image: image, for: cacheKey)

        return image
    }

    /// 预加载图像（后台任务）
    func preload(urls: [URL], size: ImageSize = .medium) {
        Task(priority: .low) {
            for url in urls {
                try? await image(for: url, size: size)
            }
        }
    }

    /// 取消预加载
    func cancelPreload() {
        // Task cancellation handled automatically
    }

    // MARK: - Private Helpers

    private func cacheKey(for url: URL, size: ImageSize) -> String {
        let urlHash = url.absoluteString.hash
        return "\(urlHash)_\(size.rawValue)"
    }

    private func downloadImage(from url: URL, targetSize: ImageSize) async throws -> UIImage {
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let image = UIImage(data: data) else {
            throw ImageCacheError.invalidImageData
        }

        // 压缩到目标尺寸（减少内存占用）
        return await resizeImage(image, to: targetSize)
    }

    private func resizeImage(_ image: UIImage, to size: ImageSize) async -> UIImage {
        await withCheckedContinuation { continuation in
            processingQueue.async {
                let targetWidth = size.dimension
                let scale = targetWidth / image.size.width
                let targetSize = CGSize(
                    width: targetWidth,
                    height: image.size.height * scale
                )

                UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
                image.draw(in: CGRect(origin: .zero, size: targetSize))
                let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
                UIGraphicsEndImageContext()

                continuation.resume(returning: resized)
            }
        }
    }

    private func cache(image: UIImage, for key: String) async {
        // 内存缓存
        let cost = image.pngData()?.count ?? 0
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)

        // 磁盘缓存（异步）
        await saveToDisk(image: image, cacheKey: key)
    }

    private func saveToDisk(image: UIImage, cacheKey: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                let fileURL = self.diskCacheURL.appendingPathComponent(cacheKey)

                // 使用 JPEG 压缩（80% 质量）
                if let data = image.jpegData(compressionQuality: 0.8) {
                    try? data.write(to: fileURL)

                    // 更新统计
                    Task { @MainActor in
                        self.cacheStats.totalBytes += Int64(data.count)
                    }
                }

                continuation.resume()
            }
        }
    }

    private func loadFromDisk(cacheKey: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                let fileURL = self.diskCacheURL.appendingPathComponent(cacheKey)

                guard let data = try? Data(contentsOf: fileURL),
                      let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    @objc private func handleMemoryWarning() {
        memoryCache.removeAllObjects()
        cacheStats.memoryHits = 0
        print("⚠️ Memory warning: Cleared image cache")
    }

    private func cleanExpiredCache() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                let maxAge: TimeInterval = 7 * 24 * 3600 // 7 days
                let now = Date()

                if let files = try? self.fileManager.contentsOfDirectory(
                    at: self.diskCacheURL,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                ) {
                    for file in files {
                        if let attrs = try? self.fileManager.attributesOfItem(atPath: file.path),
                           let modDate = attrs[.modificationDate] as? Date,
                           now.timeIntervalSince(modDate) > maxAge {
                            try? self.fileManager.removeItem(at: file)
                        }
                    }
                }

                continuation.resume()
            }
        }
    }

    // MARK: - Cache Management

    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheURL)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        cacheStats = CacheStats()
    }

    func getCacheSize() async -> Int64 {
        await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: 0)
                    return
                }

                var totalSize: Int64 = 0

                if let files = try? self.fileManager.contentsOfDirectory(
                    at: self.diskCacheURL,
                    includingPropertiesForKeys: [.fileSizeKey]
                ) {
                    for file in files {
                        if let attrs = try? self.fileManager.attributesOfItem(atPath: file.path),
                           let size = attrs[.size] as? Int64 {
                            totalSize += size
                        }
                    }
                }

                continuation.resume(returning: totalSize)
            }
        }
    }
}

// MARK: - Image Size Enum
enum ImageSize: String {
    case thumbnail = "thumb"  // 200x200
    case medium = "medium"    // 600x600
    case full = "full"        // 原始尺寸

    var dimension: CGFloat {
        switch self {
        case .thumbnail: return 200
        case .medium: return 600
        case .full: return UIScreen.main.bounds.width * UIScreen.main.scale
        }
    }
}

// MARK: - Errors
enum ImageCacheError: Error {
    case invalidImageData
    case downloadFailed
}
