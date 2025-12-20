import Foundation
import OSLog

// MARK: - Feed Performance Monitor

/// Monitors feed performance metrics for debugging and optimization
/// Tracks: feed load time, cache hit rate, error rate, network retries
/// Uses os.log for structured logging and OSSignposter for performance tracking
class FeedPerformanceMonitor {
    static let shared = FeedPerformanceMonitor()

    // MARK: - Performance Logging

    private let logger = Logger(subsystem: "com.nova.social", category: "FeedPerformance")
    private let signposter: OSSignposter

    // MARK: - Metrics Storage

    private var metrics: FeedMetrics
    private let metricsQueue = DispatchQueue(label: "com.nova.feedmetrics", qos: .utility)

    // MARK: - Initialization

    private init() {
        self.signposter = OSSignposter(logger: logger)
        self.metrics = FeedMetrics()
    }

    // MARK: - Feed Load Tracking

    /// Start tracking a feed load operation
    /// - Parameters:
    ///   - source: Source of the load (initial, refresh, pagination)
    ///   - fromCache: Whether this load is from cache
    /// - Returns: A signpost interval state for tracking this operation
    func beginFeedLoad(source: FeedLoadSource, fromCache: Bool) -> OSSignpostIntervalState {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("FeedLoad", id: signpostID)

        logger.debug("Feed load started - source: \(source.rawValue), fromCache: \(fromCache)")

        metricsQueue.async { [weak self] in
            self?.metrics.totalLoads += 1
            if fromCache {
                self?.metrics.cacheHits += 1
            }
        }

        return state
    }

    /// End tracking a feed load operation
    /// - Parameters:
    ///   - signpostID: The signpost interval state from beginFeedLoad
    ///   - success: Whether the load succeeded
    ///   - postCount: Number of posts loaded
    ///   - duration: Duration in seconds
    func endFeedLoad(signpostID: OSSignpostIntervalState, success: Bool, postCount: Int, duration: TimeInterval) {
        signposter.endInterval("FeedLoad", signpostID)

        logger.info("Feed load completed - success: \(success), posts: \(postCount), duration: \(String(format: "%.2f", duration))s")

        metricsQueue.async { [weak self] in
            guard let self = self else { return }

            if success {
                self.metrics.successfulLoads += 1
                self.metrics.totalLoadTimeMs += Int64(duration * 1000)
                self.metrics.totalPostsLoaded += postCount

                // Track average load time
                let avgLoadTime = Double(self.metrics.totalLoadTimeMs) / Double(self.metrics.successfulLoads)
                if avgLoadTime > 2000 { // Log if average exceeds 2 seconds
                    self.logger.warning("Average feed load time high: \(String(format: "%.0f", avgLoadTime))ms")
                }
            } else {
                self.metrics.failedLoads += 1
            }
        }
    }

    // MARK: - Error Tracking

    /// Record a feed error
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - context: Additional context about where the error occurred
    func recordError(_ error: Error, context: String) {
        logger.error("Feed error - context: \(context), error: \(error.localizedDescription)")

        metricsQueue.async { [weak self] in
            self?.metrics.errorCount += 1

            // Track specific error types
            if let apiError = error as? APIError {
                self?.recordAPIError(apiError)
            }
        }
    }

    private func recordAPIError(_ error: APIError) {
        switch error {
        case .timeout:
            metrics.timeoutCount += 1
        case .noConnection, .networkError:
            metrics.networkErrorCount += 1
        case .serverError(let statusCode, _):
            if statusCode >= 500 {
                metrics.serverErrorCount += 1
            }
        case .unauthorized:
            metrics.authErrorCount += 1
        default:
            break
        }
    }

    // MARK: - Network Retry Tracking

    /// Record a network retry attempt
    /// - Parameters:
    ///   - endpoint: The endpoint being retried
    ///   - attemptNumber: Which retry attempt (1, 2, 3, etc.)
    func recordRetry(endpoint: String, attemptNumber: Int) {
        logger.info("Network retry - endpoint: \(endpoint), attempt: \(attemptNumber)")

        metricsQueue.async { [weak self] in
            self?.metrics.retryCount += 1
        }
    }

    // MARK: - Cache Performance

    /// Record cache hit rate for a specific operation
    /// - Parameter hit: Whether the cache was hit
    func recordCacheAccess(hit: Bool) {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }

            if hit {
                self.metrics.cacheHits += 1
            } else {
                self.metrics.cacheMisses += 1
            }

            // Log cache hit rate periodically
            let total = self.metrics.cacheHits + self.metrics.cacheMisses
            if total > 0 && total % 10 == 0 {
                let hitRate = Double(self.metrics.cacheHits) / Double(total) * 100
                self.logger.info("Cache hit rate: \(String(format: "%.1f", hitRate))% (\(self.metrics.cacheHits)/\(total))")
            }
        }
    }

    // MARK: - Image Loading Tracking

    /// Begin tracking image prefetch operation
    func beginImagePrefetch(urlCount: Int) -> OSSignpostIntervalState {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("ImagePrefetch", id: signpostID)

        logger.debug("Image prefetch started - urls: \(urlCount)")
        return state
    }

    /// End tracking image prefetch operation
    func endImagePrefetch(signpostID: OSSignpostIntervalState, successCount: Int, failCount: Int) {
        signposter.endInterval("ImagePrefetch", signpostID)

        logger.info("Image prefetch completed - success: \(successCount), failed: \(failCount)")

        metricsQueue.async { [weak self] in
            self?.metrics.imagePrefetchSuccess += successCount
            self?.metrics.imagePrefetchFailed += failCount
        }
    }

    // MARK: - Metrics Reporting

    /// Get current metrics snapshot
    func getMetrics() -> FeedMetrics {
        metricsQueue.sync {
            return metrics
        }
    }

    /// Get formatted metrics report for debugging
    func getMetricsReport() -> String {
        let m = getMetrics()

        let totalLoads = m.totalLoads
        let successRate = totalLoads > 0 ? Double(m.successfulLoads) / Double(totalLoads) * 100 : 0
        let avgLoadTime = m.successfulLoads > 0 ? Double(m.totalLoadTimeMs) / Double(m.successfulLoads) : 0
        let totalCacheAccess = m.cacheHits + m.cacheMisses
        let cacheHitRate = totalCacheAccess > 0 ? Double(m.cacheHits) / Double(totalCacheAccess) * 100 : 0
        let errorRate = totalLoads > 0 ? Double(m.errorCount) / Double(totalLoads) * 100 : 0

        return """
        ===== Feed Performance Metrics =====
        Loads: \(totalLoads) total (\(m.successfulLoads) success, \(m.failedLoads) failed)
        Success Rate: \(String(format: "%.1f", successRate))%
        Avg Load Time: \(String(format: "%.0f", avgLoadTime))ms
        Posts Loaded: \(m.totalPostsLoaded)

        Cache Performance:
        - Hit Rate: \(String(format: "%.1f", cacheHitRate))% (\(m.cacheHits)/\(totalCacheAccess))

        Errors:
        - Total: \(m.errorCount) (\(String(format: "%.1f", errorRate))% error rate)
        - Network: \(m.networkErrorCount)
        - Timeout: \(m.timeoutCount)
        - Server: \(m.serverErrorCount)
        - Auth: \(m.authErrorCount)
        - Retries: \(m.retryCount)

        Image Prefetch:
        - Success: \(m.imagePrefetchSuccess)
        - Failed: \(m.imagePrefetchFailed)
        ===================================
        """
    }

    /// Log current metrics report
    func logMetrics() {
        logger.info("\n\(self.getMetricsReport())")
    }

    /// Reset all metrics (for testing or new session)
    func resetMetrics() {
        metricsQueue.async { [weak self] in
            self?.metrics = FeedMetrics()
            self?.logger.info("Metrics reset")
        }
    }
}

// MARK: - Feed Load Source

enum FeedLoadSource: String {
    case initial = "initial"
    case refresh = "refresh"
    case pagination = "pagination"
    case channelSwitch = "channel_switch"
}

// MARK: - Feed Metrics

struct FeedMetrics {
    // Load metrics
    var totalLoads: Int = 0
    var successfulLoads: Int = 0
    var failedLoads: Int = 0
    var totalLoadTimeMs: Int64 = 0
    var totalPostsLoaded: Int = 0

    // Cache metrics
    var cacheHits: Int = 0
    var cacheMisses: Int = 0

    // Error metrics
    var errorCount: Int = 0
    var networkErrorCount: Int = 0
    var timeoutCount: Int = 0
    var serverErrorCount: Int = 0
    var authErrorCount: Int = 0
    var retryCount: Int = 0

    // Image loading metrics
    var imagePrefetchSuccess: Int = 0
    var imagePrefetchFailed: Int = 0

    // Computed metrics
    var averageLoadTimeMs: Double {
        guard successfulLoads > 0 else { return 0 }
        return Double(totalLoadTimeMs) / Double(successfulLoads)
    }

    var cacheHitRate: Double {
        let total = cacheHits + cacheMisses
        guard total > 0 else { return 0 }
        return Double(cacheHits) / Double(total)
    }

    var successRate: Double {
        guard totalLoads > 0 else { return 0 }
        return Double(successfulLoads) / Double(totalLoads)
    }

    var errorRate: Double {
        guard totalLoads > 0 else { return 0 }
        return Double(errorCount) / Double(totalLoads)
    }
}
