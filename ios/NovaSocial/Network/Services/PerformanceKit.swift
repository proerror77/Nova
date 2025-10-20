import Foundation

/// PerformanceKit - 性能优化系统统一入口
/// 简化配置和初始化流程
final class PerformanceKit {
    // MARK: - Shared Components

    static let cache = CacheManager(defaultTTL: CacheTTL.feed)
    static let deduplicator = RequestDeduplicator()
    static let networkMonitor = NetworkMonitor.shared
    static let metrics = PerformanceMetrics.shared

    // MARK: - Configuration

    private static var isConfigured = false

    /// 一键配置所有性能优化组件
    /// 在 AppDelegate.application(_:didFinishLaunchingWithOptions:) 中调用
    static func configure(enableDebug: Bool = false) {
        guard !isConfigured else {
            Logger.log("⚠️ PerformanceKit already configured", level: .warning)
            return
        }

        // 1. 配置 URLCache（图片和资源缓存）
        URLCacheConfig.configure()

        // 2. 启动网络监听
        networkMonitor.startMonitoring()

        // 3. 配置网络恢复自动重试
        setupNetworkRecoveryHandling()

        // 4. 启用定期缓存清理
        startPeriodicCacheCleanup()

        #if DEBUG
        if enableDebug {
            // 5. 启用性能调试（仅 Debug 模式）
            setupDebugTools()
        }
        #endif

        isConfigured = true
        Logger.log("✅ PerformanceKit configured successfully", level: .info)
    }

    // MARK: - Private Setup

    private static func setupNetworkRecoveryHandling() {
        networkMonitor.onConnectionChanged = { isConnected, connectionType in
            if isConnected {
                Logger.log("🌐 Network recovered (\(connectionType))", level: .info)
                // 可以在这里触发待处理的请求
            } else {
                Logger.log("📡 Network disconnected", level: .warning)
            }
        }
    }

    private static func startPeriodicCacheCleanup() {
        // 每 5 分钟清理一次过期缓存
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task {
                await cache.cleanup()
            }
        }
    }

    #if DEBUG
    private static func setupDebugTools() {
        // 每 60 秒打印一次性能统计
        PerformanceDebugView.startAutoLogging(interval: 60)

        // 打印初始配置
        print("""

        ╔═══════════════════════════════════════════════════════════════╗
        ║              PERFORMANCE KIT DEBUG MODE                       ║
        ╠═══════════════════════════════════════════════════════════════╣
        ║ ✅ URLCache configured                                        ║
        ║ ✅ NetworkMonitor started                                     ║
        ║ ✅ Auto cache cleanup enabled (5 min)                         ║
        ║ ✅ Performance logging enabled (60 sec)                       ║
        ╠═══════════════════════════════════════════════════════════════╣
        ║ Debug Commands:                                               ║
        ║   PerformanceDebugView.printStats()                           ║
        ║   PerformanceDebugView.printSlowRequests()                    ║
        ║   PerformanceRecommendations.printRecommendations()           ║
        ╚═══════════════════════════════════════════════════════════════╝

        """)
    }
    #endif

    // MARK: - Utilities

    /// 获取完整的性能报告
    static func getPerformanceReport() async -> PerformanceReport {
        let metricsStats = await metrics.getStats()
        let cacheStats = await cache.getStats()
        let urlCacheStats = URLCacheConfig.shared.getCacheStats()
        let slowRequests = await metrics.getSlowRequests(threshold: 1.0)
        let recommendations = await PerformanceRecommendations.analyze()

        return PerformanceReport(
            metrics: metricsStats,
            cache: cacheStats,
            urlCache: urlCacheStats,
            slowRequests: slowRequests,
            recommendations: recommendations,
            networkStatus: NetworkStatus(
                isConnected: networkMonitor.isConnected,
                connectionType: networkMonitor.connectionType
            )
        )
    }

    /// 重置所有性能数据（用于测试）
    static func reset() async {
        await cache.clear()
        await deduplicator.cancelAll()
        await metrics.reset()
        URLCacheConfig.shared.clearCache()

        Logger.log("🔄 PerformanceKit reset complete", level: .info)
    }
}

// MARK: - Performance Report

struct PerformanceReport {
    let metrics: PerformanceStats
    let cache: CacheStats
    let urlCache: URLCacheStats
    let slowRequests: [RequestMetric]
    let recommendations: [String]
    let networkStatus: NetworkStatus

    var description: String {
        """
        ╔═══════════════════════════════════════════════════════════════╗
        ║                    PERFORMANCE REPORT                         ║
        ╠═══════════════════════════════════════════════════════════════╣

        \(metrics.description)

        ╠═══════════════════════════════════════════════════════════════╣
        ║ CACHE STATISTICS                                              ║
        ╠═══════════════════════════════════════════════════════════════╣
        ║ In-Memory Entries: \(cache.totalEntries)                                      ║
        ║                                                               ║
        \(urlCache.description)

        ╠═══════════════════════════════════════════════════════════════╣
        ║ NETWORK STATUS                                                ║
        ╠═══════════════════════════════════════════════════════════════╣
        \(networkStatus.description)

        \(slowRequests.isEmpty ? "" : """
        ╠═══════════════════════════════════════════════════════════════╣
        ║ SLOW REQUESTS (\(slowRequests.count))                                            ║
        ╠═══════════════════════════════════════════════════════════════╣
        \(slowRequests.prefix(5).map { "║ " + $0.description.padding(toLength: 61, withPad: " ", startingAt: 0) + "║" }.joined(separator: "\n"))
        """)

        ╠═══════════════════════════════════════════════════════════════╣
        ║ RECOMMENDATIONS                                               ║
        ╠═══════════════════════════════════════════════════════════════╣
        \(recommendations.map { "║ " + $0.padding(toLength: 61, withPad: " ", startingAt: 0) + "║" }.joined(separator: "\n"))
        ╚═══════════════════════════════════════════════════════════════╝
        """
    }
}

// MARK: - Network Status

struct NetworkStatus {
    let isConnected: Bool
    let connectionType: ConnectionType

    var description: String {
        let status = isConnected ? "🟢 Connected" : "🔴 Disconnected"
        return "║ Status: \(status) (\(connectionType.rawValue))                                    ║"
    }
}

// MARK: - Convenience Extensions

extension PerformanceKit {
    /// 创建优化的 Repository 实例
    static func createOptimizedRepository<T: RepositoryProtocol>(_ type: T.Type) -> T {
        // Repository 应该使用共享的 cache 和 deduplicator
        return T.init(cache: cache, deduplicator: deduplicator)
    }
}

// MARK: - Repository Protocol

protocol RepositoryProtocol {
    init(cache: CacheManager, deduplicator: RequestDeduplicator)
}

// MARK: - Global Access (Optional)

extension CacheManager {
    /// 全局共享实例
    static let shared = PerformanceKit.cache
}

extension RequestDeduplicator {
    /// 全局共享实例
    static let shared = PerformanceKit.deduplicator
}
