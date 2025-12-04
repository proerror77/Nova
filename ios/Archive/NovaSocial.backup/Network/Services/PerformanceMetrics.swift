import Foundation

/// 性能指标收集器 - 追踪网络和缓存性能
actor PerformanceMetrics {
    // MARK: - Shared Instance

    static let shared = PerformanceMetrics()

    // MARK: - Metrics Data

    private var requestMetrics: [RequestMetric] = []
    private var cacheHits = 0
    private var cacheMisses = 0
    private var totalBytesTransferred = 0

    private let maxMetricsHistory = 100 // 保留最近 100 条记录

    // MARK: - Request Tracking

    /// 记录请求指标
    func recordRequest(
        path: String,
        method: HTTPMethod,
        duration: TimeInterval,
        statusCode: Int?,
        bytesTransferred: Int,
        fromCache: Bool
    ) {
        let metric = RequestMetric(
            path: path,
            method: method,
            duration: duration,
            statusCode: statusCode,
            bytesTransferred: bytesTransferred,
            fromCache: fromCache,
            timestamp: Date()
        )

        requestMetrics.append(metric)

        // 限制历史记录数量
        if requestMetrics.count > maxMetricsHistory {
            requestMetrics.removeFirst()
        }

        // 更新统计
        totalBytesTransferred += bytesTransferred

        if fromCache {
            cacheHits += 1
        }
    }

    /// 记录缓存命中
    func recordCacheHit() {
        cacheHits += 1
    }

    /// 记录缓存未命中
    func recordCacheMiss() {
        cacheMisses += 1
    }

    // MARK: - Statistics

    /// 获取性能统计
    func getStats() -> PerformanceStats {
        let avgDuration = requestMetrics.isEmpty ? 0 : requestMetrics.reduce(0) { $0 + $1.duration } / Double(requestMetrics.count)

        let cacheHitRate = cacheHits + cacheMisses == 0 ? 0 : Double(cacheHits) / Double(cacheHits + cacheMisses) * 100

        return PerformanceStats(
            totalRequests: requestMetrics.count,
            averageDuration: avgDuration,
            cacheHitRate: cacheHitRate,
            totalBytesTransferred: totalBytesTransferred,
            recentMetrics: Array(requestMetrics.suffix(10))
        )
    }

    /// 获取慢请求列表
    func getSlowRequests(threshold: TimeInterval = 1.0) -> [RequestMetric] {
        requestMetrics.filter { $0.duration > threshold }
    }

    /// 重置所有统计
    func reset() {
        requestMetrics.removeAll()
        cacheHits = 0
        cacheMisses = 0
        totalBytesTransferred = 0
    }
}

// MARK: - Request Metric

struct RequestMetric {
    let path: String
    let method: HTTPMethod
    let duration: TimeInterval
    let statusCode: Int?
    let bytesTransferred: Int
    let fromCache: Bool
    let timestamp: Date

    var durationMs: Int {
        Int(duration * 1000)
    }

    var description: String {
        let cacheStatus = fromCache ? "🟢 CACHE" : "🔴 NET"
        let status = statusCode.map { "\($0)" } ?? "N/A"
        return "\(cacheStatus) \(method.rawValue) \(path) - \(durationMs)ms (\(status))"
    }
}

// MARK: - Performance Stats

struct PerformanceStats {
    let totalRequests: Int
    let averageDuration: TimeInterval
    let cacheHitRate: Double
    let totalBytesTransferred: Int
    let recentMetrics: [RequestMetric]

    var averageDurationMs: Int {
        Int(averageDuration * 1000)
    }

    var totalMB: Double {
        Double(totalBytesTransferred) / 1024 / 1024
    }

    var description: String {
        """
        📊 Performance Stats
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Total Requests: \(totalRequests)
        Avg Duration: \(averageDurationMs) ms
        Cache Hit Rate: \(String(format: "%.1f", cacheHitRate))%
        Data Transferred: \(String(format: "%.2f", totalMB)) MB

        Recent Requests:
        \(recentMetrics.map { "  • " + $0.description }.joined(separator: "\n"))
        """
    }
}

// MARK: - Performance Timer

/// 性能计时器 - 简化请求时间测量
final class PerformanceTimer {
    private let startTime: Date
    private let path: String
    private let method: HTTPMethod

    init(path: String, method: HTTPMethod = .get) {
        self.startTime = Date()
        self.path = path
        self.method = method
    }

    /// 停止计时并记录指标
    func stop(statusCode: Int?, bytesTransferred: Int = 0, fromCache: Bool = false) {
        let duration = Date().timeIntervalSince(startTime)

        Task {
            await PerformanceMetrics.shared.recordRequest(
                path: path,
                method: method,
                duration: duration,
                statusCode: statusCode,
                bytesTransferred: bytesTransferred,
                fromCache: fromCache
            )
        }

        // 慢请求警告
        if duration > 2.0 {
            Logger.log("🐌 Slow request detected: \(path) took \(Int(duration * 1000))ms", level: .warning)
        }
    }
}

// MARK: - Convenience Extensions

extension PerformanceTimer {
    /// 执行并测量异步操作
    static func measure<T>(
        path: String,
        method: HTTPMethod = .get,
        operation: () async throws -> T
    ) async rethrows -> T {
        let timer = PerformanceTimer(path: path, method: method)

        do {
            let result = try await operation()
            timer.stop(statusCode: 200)
            return result
        } catch {
            timer.stop(statusCode: nil)
            throw error
        }
    }
}
