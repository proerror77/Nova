import Foundation

/// URL 缓存配置 - 图片和资源缓存
final class URLCacheConfig {
    // MARK: - Shared Instance

    static let shared = URLCacheConfig()

    // MARK: - Properties

    private(set) var urlCache: URLCache

    // MARK: - Configuration

    private let memoryCacheSize = 50 * 1024 * 1024    // 50 MB
    private let diskCacheSize = 200 * 1024 * 1024     // 200 MB

    // MARK: - Initialization

    private init() {
        // 创建自定义 URLCache
        self.urlCache = URLCache(
            memoryCapacity: memoryCacheSize,
            diskCapacity: diskCacheSize,
            diskPath: "nova_cache"
        )

        // 设置为全局 URLCache
        URLCache.shared = urlCache

        Logger.log("🗄️ URLCache configured (Memory: \(memoryCacheSize / 1024 / 1024) MB, Disk: \(diskCacheSize / 1024 / 1024) MB)", level: .info)
    }

    // MARK: - Public API

    /// 配置缓存策略
    static func configure() {
        _ = shared // 触发初始化
    }

    /// 清除所有缓存
    func clearCache() {
        urlCache.removeAllCachedResponses()
        Logger.log("🧹 URLCache cleared", level: .info)
    }

    /// 获取缓存统计
    func getCacheStats() -> URLCacheStats {
        URLCacheStats(
            currentMemoryUsage: urlCache.currentMemoryUsage,
            currentDiskUsage: urlCache.currentDiskUsage,
            maxMemoryUsage: urlCache.memoryCapacity,
            maxDiskUsage: urlCache.diskCapacity
        )
    }
}

// MARK: - URLCache Stats

struct URLCacheStats {
    let currentMemoryUsage: Int
    let currentDiskUsage: Int
    let maxMemoryUsage: Int
    let maxDiskUsage: Int

    var memoryUsagePercent: Double {
        Double(currentMemoryUsage) / Double(maxMemoryUsage) * 100
    }

    var diskUsagePercent: Double {
        Double(currentDiskUsage) / Double(maxDiskUsage) * 100
    }

    var description: String {
        """
        URLCache Stats:
        - Memory: \(currentMemoryUsage / 1024 / 1024) MB / \(maxMemoryUsage / 1024 / 1024) MB (\(String(format: "%.1f", memoryUsagePercent))%)
        - Disk: \(currentDiskUsage / 1024 / 1024) MB / \(maxDiskUsage / 1024 / 1024) MB (\(String(format: "%.1f", diskUsagePercent))%)
        """
    }
}

// MARK: - URLRequest Extension

extension URLRequest {
    /// 创建带缓存策略的请求
    static func cachedRequest(url: URL, cachePolicy: CachePolicy = .default) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = cachePolicy.urlRequestCachePolicy
        return request
    }
}

// MARK: - Cache Policy

enum CachePolicy {
    case `default`              // 使用默认缓存策略
    case reloadIgnoringCache    // 忽略缓存，总是从服务器加载
    case returnCacheElseLoad    // 优先使用缓存，缓存不存在时加载
    case onlyFromCache          // 仅使用缓存，不发起网络请求

    var urlRequestCachePolicy: URLRequest.CachePolicy {
        switch self {
        case .default:
            return .useProtocolCachePolicy
        case .reloadIgnoringCache:
            return .reloadIgnoringLocalCacheData
        case .returnCacheElseLoad:
            return .returnCacheDataElseLoad
        case .onlyFromCache:
            return .returnCacheDataDontLoad
        }
    }
}
