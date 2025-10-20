import Foundation

#if DEBUG
/// 性能调试视图 - 用于开发时查看性能指标
/// 使用方法：在 AppDelegate 或 SceneDelegate 中调用 PerformanceDebugView.show()
final class PerformanceDebugView {
    static let shared = PerformanceDebugView()

    private init() {}

    /// 显示性能统计
    static func printStats() {
        Task {
            let stats = await PerformanceMetrics.shared.getStats()
            let cacheStats = await CacheManager().getStats()
            let urlCacheStats = URLCacheConfig.shared.getCacheStats()

            print("""

            ╔═══════════════════════════════════════════════════════════════╗
            ║                    PERFORMANCE STATISTICS                     ║
            ╠═══════════════════════════════════════════════════════════════╣
            \(stats.description)
            ╠═══════════════════════════════════════════════════════════════╣
            ║ CACHE STATISTICS                                              ║
            ╠═══════════════════════════════════════════════════════════════╣
            ║ In-Memory Cache: \(cacheStats.totalEntries) entries                               ║
            ║                                                               ║
            \(urlCacheStats.description)
            ╚═══════════════════════════════════════════════════════════════╝

            """)
        }
    }

    /// 打印慢请求列表
    static func printSlowRequests(threshold: TimeInterval = 1.0) {
        Task {
            let slowRequests = await PerformanceMetrics.shared.getSlowRequests(threshold: threshold)

            if slowRequests.isEmpty {
                print("✅ No slow requests detected (threshold: \(threshold)s)")
            } else {
                print("""

                ⚠️  SLOW REQUESTS DETECTED
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                Threshold: \(threshold)s
                Count: \(slowRequests.count)

                \(slowRequests.map { "  • " + $0.description }.joined(separator: "\n"))
                ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                """)
            }
        }
    }

    /// 重置所有统计
    static func resetStats() {
        Task {
            await PerformanceMetrics.shared.reset()
            print("🔄 Performance stats reset")
        }
    }

    /// 清除所有缓存
    static func clearAllCaches() {
        Task {
            await CacheManager().clear()
            URLCacheConfig.shared.clearCache()
            print("🧹 All caches cleared")
        }
    }

    /// 启用自动统计打印（每 30 秒）
    static func startAutoLogging(interval: TimeInterval = 30) {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            printStats()
        }
        print("📊 Auto-logging enabled (interval: \(interval)s)")
    }
}

// MARK: - Console Commands

extension PerformanceDebugView {
    /// 可以在 LLDB 中调用的命令
    ///
    /// 使用方法：
    /// ```
    /// (lldb) po PerformanceDebugView.printStats()
    /// (lldb) po PerformanceDebugView.printSlowRequests()
    /// (lldb) po PerformanceDebugView.clearAllCaches()
    /// (lldb) po PerformanceDebugView.resetStats()
    /// ```
}
#endif

// MARK: - Performance Recommendations

/// 性能优化建议生成器
final class PerformanceRecommendations {
    static func analyze() async -> [String] {
        var recommendations: [String] = []

        let stats = await PerformanceMetrics.shared.getStats()
        let slowRequests = await PerformanceMetrics.shared.getSlowRequests(threshold: 1.0)
        let urlCacheStats = URLCacheConfig.shared.getCacheStats()

        // 分析缓存命中率
        if stats.cacheHitRate < 50 {
            recommendations.append("⚠️  Cache hit rate is low (\(String(format: "%.1f", stats.cacheHitRate))%). Consider increasing TTL or caching more resources.")
        } else if stats.cacheHitRate > 80 {
            recommendations.append("✅ Excellent cache hit rate (\(String(format: "%.1f", stats.cacheHitRate))%)")
        }

        // 分析平均请求时间
        if stats.averageDurationMs > 500 {
            recommendations.append("⚠️  Average request time is high (\(stats.averageDurationMs)ms). Consider optimizing backend APIs or using pagination.")
        } else if stats.averageDurationMs < 200 {
            recommendations.append("✅ Fast average response time (\(stats.averageDurationMs)ms)")
        }

        // 分析慢请求
        if !slowRequests.isEmpty {
            recommendations.append("⚠️  \(slowRequests.count) slow requests detected. Review these endpoints:")
            slowRequests.forEach { metric in
                recommendations.append("   • \(metric.path) (\(metric.durationMs)ms)")
            }
        }

        // 分析磁盘缓存使用
        if urlCacheStats.diskUsagePercent > 90 {
            recommendations.append("⚠️  Disk cache usage is high (\(String(format: "%.1f", urlCacheStats.diskUsagePercent))%). Consider clearing old caches.")
        }

        // 分析数据传输
        if stats.totalMB > 100 {
            recommendations.append("⚠️  High data usage (\(String(format: "%.2f", stats.totalMB)) MB). Consider implementing response compression or reducing payload sizes.")
        }

        if recommendations.isEmpty {
            recommendations.append("✅ All performance metrics look good!")
        }

        return recommendations
    }

    static func printRecommendations() {
        Task {
            let recommendations = await analyze()

            print("""

            ╔═══════════════════════════════════════════════════════════════╗
            ║              PERFORMANCE RECOMMENDATIONS                      ║
            ╠═══════════════════════════════════════════════════════════════╣
            \(recommendations.map { "║ " + $0.padding(toLength: 61, withPad: " ", startingAt: 0) + "║" }.joined(separator: "\n"))
            ╚═══════════════════════════════════════════════════════════════╝

            """)
        }
    }
}
