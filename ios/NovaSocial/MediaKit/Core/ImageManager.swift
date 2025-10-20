import UIKit
import Foundation

/// 图片管理器 - 处理所有图片操作的核心单例
///
/// Linus 哲学：简单的数据结构，没有特殊情况
/// - 内存缓存 -> 磁盘缓存 -> 网络加载（清晰的数据流）
/// - 统一的错误处理
/// - 零边界情况的设计
@MainActor
final class ImageManager: ObservableObject {
    static let shared = ImageManager()

    // MARK: - Properties

    /// 内存缓存 - 第一层，最快
    private let memoryCache = NSCache<NSString, UIImage>()

    /// 磁盘缓存目录
    private let diskCacheURL: URL

    /// 下载队列 - 控制并发
    private let downloadQueue = DispatchQueue(label: "com.nova.imagemanager", attributes: .concurrent)

    /// 正在进行的下载任务
    private var activeTasks: [String: Task<UIImage, Error>] = [:]

    /// 性能指标
    @Published private(set) var metrics = ImageMetrics()

    // MARK: - Configuration

    struct Config {
        var memoryCacheLimit: Int = 100 * 1024 * 1024  // 100MB
        var diskCacheLimit: Int = 500 * 1024 * 1024    // 500MB
        var maxConcurrentDownloads: Int = 4
        var downloadTimeout: TimeInterval = 30
        var enableMetrics: Bool = true
    }

    private let config: Config

    // MARK: - Initialization

    init(config: Config = Config()) {
        self.config = config

        // 设置内存缓存限制
        memoryCache.totalCostLimit = config.memoryCacheLimit

        // 设置磁盘缓存目录
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheURL = cacheDir.appendingPathComponent("ImageCache", isDirectory: true)

        // 创建磁盘缓存目录
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        // 清理过期缓存
        Task {
            await cleanExpiredCache()
        }
    }

    // MARK: - Public API

    /// 加载图片 - 统一入口
    /// - Parameters:
    ///   - url: 图片 URL
    ///   - placeholder: 占位图
    /// - Returns: 加载的图片
    func loadImage(url: String, placeholder: UIImage? = nil) async throws -> UIImage {
        let startTime = Date()

        // 1. 检查内存缓存
        if let cached = memoryCache.object(forKey: url as NSString) {
            updateMetrics(cacheHit: true, loadTime: Date().timeIntervalSince(startTime))
            return cached
        }

        // 2. 检查磁盘缓存
        if let diskCached = await loadFromDisk(url: url) {
            // 回填内存缓存
            memoryCache.setObject(diskCached, forKey: url as NSString)
            updateMetrics(cacheHit: true, loadTime: Date().timeIntervalSince(startTime))
            return diskCached
        }

        // 3. 检查是否已有下载任务
        if let existingTask = activeTasks[url] {
            return try await existingTask.value
        }

        // 4. 网络下载
        let downloadTask = Task<UIImage, Error> {
            let image = try await downloadImage(url: url)

            // 缓存到内存和磁盘
            memoryCache.setObject(image, forKey: url as NSString)
            await saveToDisk(image: image, url: url)

            // 移除任务引用
            activeTasks.removeValue(forKey: url)

            updateMetrics(cacheHit: false, loadTime: Date().timeIntervalSince(startTime))
            return image
        }

        activeTasks[url] = downloadTask
        return try await downloadTask.value
    }

    /// 预加载图片 - 用于预测性加载
    func prefetchImages(urls: [String]) {
        Task {
            for url in urls {
                // 只预加载未缓存的图片
                if memoryCache.object(forKey: url as NSString) == nil {
                    try? await loadImage(url: url)
                }
            }
        }
    }

    /// 取消下载
    func cancelDownload(url: String) {
        activeTasks[url]?.cancel()
        activeTasks.removeValue(forKey: url)
    }

    /// 清空缓存
    func clearCache(includeMemory: Bool = true, includeDisk: Bool = true) async {
        if includeMemory {
            memoryCache.removeAllObjects()
        }

        if includeDisk {
            try? FileManager.default.removeItem(at: diskCacheURL)
            try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        }
    }

    /// 获取缓存大小
    func getCacheSize() async -> (memory: Int, disk: Int) {
        let diskSize = await getDiskCacheSize()
        return (memory: 0, disk: diskSize) // 内存缓存大小难以精确计算
    }

    // MARK: - Private Helpers

    private func downloadImage(url: String) async throws -> UIImage {
        guard let imageURL = URL(string: url) else {
            throw ImageError.invalidURL
        }

        var request = URLRequest(url: imageURL)
        request.timeoutInterval = config.downloadTimeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ImageError.downloadFailed
        }

        guard let image = UIImage(data: data) else {
            throw ImageError.invalidImageData
        }

        return image
    }

    private func loadFromDisk(url: String) async -> UIImage? {
        let cacheKey = url.md5Hash
        let fileURL = diskCacheURL.appendingPathComponent(cacheKey)

        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    private func saveToDisk(image: UIImage, url: String) async {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }

        let cacheKey = url.md5Hash
        let fileURL = diskCacheURL.appendingPathComponent(cacheKey)

        try? data.write(to: fileURL)
    }

    private func getDiskCacheSize() async -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + size
        }
    }

    private func cleanExpiredCache() async {
        // 检查磁盘缓存大小
        let diskSize = await getDiskCacheSize()

        if diskSize > config.diskCacheLimit {
            // 清理最旧的文件
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: diskCacheURL,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            ) else { return }

            let sortedFiles = files.sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 < date2
            }

            var currentSize = diskSize
            for file in sortedFiles {
                guard currentSize > config.diskCacheLimit / 2 else { break }

                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                try? FileManager.default.removeItem(at: file)
                currentSize -= size
            }
        }
    }

    private func updateMetrics(cacheHit: Bool, loadTime: TimeInterval) {
        guard config.enableMetrics else { return }

        metrics.totalLoads += 1
        if cacheHit {
            metrics.cacheHits += 1
        } else {
            metrics.cacheMisses += 1
        }
        metrics.averageLoadTime = (metrics.averageLoadTime * Double(metrics.totalLoads - 1) + loadTime) / Double(metrics.totalLoads)
    }
}

// MARK: - Metrics

struct ImageMetrics: Codable {
    var totalLoads: Int = 0
    var cacheHits: Int = 0
    var cacheMisses: Int = 0
    var averageLoadTime: TimeInterval = 0

    var hitRate: Double {
        guard totalLoads > 0 else { return 0 }
        return Double(cacheHits) / Double(totalLoads)
    }
}

// MARK: - Errors

enum ImageError: LocalizedError {
    case invalidURL
    case downloadFailed
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid image URL"
        case .downloadFailed:
            return "Failed to download image"
        case .invalidImageData:
            return "Invalid image data"
        }
    }
}

// MARK: - String Extension

private extension String {
    var md5Hash: String {
        // 简单的哈希实现，生产环境应使用 CryptoKit
        return self.data(using: .utf8)?.base64EncodedString() ?? self
    }
}
