import Foundation

/// 通用缓存管理器 - 支持 TTL 和自动过期
/// 使用 Actor 保证线程安全，避免 NSLock 的复杂性
actor CacheManager {
    // MARK: - Cache Entry

    private struct CacheEntry<T> {
        let value: T
        let expiration: Date

        var isExpired: Bool {
            Date() > expiration
        }
    }

    // MARK: - Properties

    private var cache: [String: Any] = [:]
    private let defaultTTL: TimeInterval

    // MARK: - Initialization

    init(defaultTTL: TimeInterval = 300) { // 默认 5 分钟
        self.defaultTTL = defaultTTL
    }

    // MARK: - Public API

    /// 存储数据到缓存
    func set<T>(_ value: T, forKey key: String, ttl: TimeInterval? = nil) {
        let expiration = Date().addingTimeInterval(ttl ?? defaultTTL)
        let entry = CacheEntry(value: value, expiration: expiration)
        cache[key] = entry

        Logger.log("💾 Cache SET: \(key) (TTL: \(ttl ?? defaultTTL)s)", level: .debug)
    }

    /// 从缓存获取数据
    func get<T>(forKey key: String) -> T? {
        guard let entry = cache[key] as? CacheEntry<T> else {
            Logger.log("❌ Cache MISS: \(key)", level: .debug)
            return nil
        }

        if entry.isExpired {
            Logger.log("⏰ Cache EXPIRED: \(key)", level: .debug)
            cache.removeValue(forKey: key)
            return nil
        }

        Logger.log("✅ Cache HIT: \(key)", level: .debug)
        return entry.value
    }

    /// 移除特定 key 的缓存
    func remove(forKey key: String) {
        cache.removeValue(forKey: key)
        Logger.log("🗑️ Cache REMOVE: \(key)", level: .debug)
    }

    /// 清空所有缓存
    func clear() {
        cache.removeAll()
        Logger.log("🧹 Cache CLEAR: All entries removed", level: .debug)
    }

    /// 清理过期的缓存条目
    func cleanup() {
        var expiredKeys: [String] = []

        for (key, value) in cache {
            // Type erasure workaround - check expiration via reflection
            if let entry = value as? any ExpirableEntry, entry.isExpiredValue {
                expiredKeys.append(key)
            }
        }

        expiredKeys.forEach { cache.removeValue(forKey: $0) }

        if !expiredKeys.isEmpty {
            Logger.log("🧹 Cache CLEANUP: Removed \(expiredKeys.count) expired entries", level: .debug)
        }
    }

    /// 获取缓存统计信息
    func getStats() -> CacheStats {
        CacheStats(totalEntries: cache.count)
    }
}

// MARK: - Helper Protocol

private protocol ExpirableEntry {
    var isExpiredValue: Bool { get }
}

extension CacheManager.CacheEntry: ExpirableEntry {
    var isExpiredValue: Bool { isExpired }
}

// MARK: - Cache Stats

struct CacheStats {
    let totalEntries: Int
}

// MARK: - Cache Keys

/// 缓存键常量
enum CacheKey {
    static func feed(cursor: String?) -> String {
        "feed_\(cursor ?? "first")"
    }

    static func exploreFeed(page: Int) -> String {
        "explore_\(page)"
    }

    static func userProfile(userId: String) -> String {
        "user_\(userId)"
    }

    static func notifications() -> String {
        "notifications"
    }
}

// MARK: - TTL Presets

/// TTL 预设值
enum CacheTTL {
    static let feed: TimeInterval = 300           // 5 分钟
    static let exploreFeed: TimeInterval = 600    // 10 分钟
    static let userProfile: TimeInterval = 1800   // 30 分钟
    static let notifications: TimeInterval = 60   // 1 分钟
    static let image: TimeInterval = 86400        // 24 小时
}
