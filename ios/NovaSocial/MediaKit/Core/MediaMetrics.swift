import Foundation
import SwiftUI

/// 媒体性能监控 - Linus 风格：简单的数据收集，清晰的报告
///
/// 核心功能：
/// - 图片加载耗时
/// - 缓存命中率
/// - 内存使用
/// - 网络流量
@MainActor
final class MediaMetrics: ObservableObject {
    static let shared = MediaMetrics()

    // MARK: - Published Properties

    @Published private(set) var imageLoadMetrics = ImageLoadMetrics()
    @Published private(set) var cacheMetrics = CacheMetrics()
    @Published private(set) var networkMetrics = NetworkMetrics()
    @Published private(set) var memoryMetrics = MemoryMetrics()

    // MARK: - Private Properties

    private var isMonitoring = false
    private var memoryUpdateTimer: Timer?

    // MARK: - Public API

    /// 开始监控
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // 定期更新内存指标
        memoryUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMemoryMetrics()
            }
        }
    }

    /// 停止监控
    func stopMonitoring() {
        isMonitoring = false
        memoryUpdateTimer?.invalidate()
        memoryUpdateTimer = nil
    }

    /// 记录图片加载
    func recordImageLoad(url: String, duration: TimeInterval, cacheHit: Bool, size: Int) {
        imageLoadMetrics.totalLoads += 1
        imageLoadMetrics.totalDuration += duration

        if cacheHit {
            cacheMetrics.hits += 1
        } else {
            cacheMetrics.misses += 1
            networkMetrics.totalBytesDownloaded += size
        }
    }

    /// 记录图片上传
    func recordImageUpload(size: Int, duration: TimeInterval, success: Bool) {
        networkMetrics.totalBytesUploaded += size

        if success {
            imageLoadMetrics.successfulUploads += 1
        } else {
            imageLoadMetrics.failedUploads += 1
        }
    }

    /// 获取性能报告
    func getPerformanceReport() -> PerformanceReport {
        PerformanceReport(
            imageLoad: imageLoadMetrics,
            cache: cacheMetrics,
            network: networkMetrics,
            memory: memoryMetrics,
            timestamp: Date()
        )
    }

    /// 重置所有指标
    func reset() {
        imageLoadMetrics = ImageLoadMetrics()
        cacheMetrics = CacheMetrics()
        networkMetrics = NetworkMetrics()
        memoryMetrics = MemoryMetrics()
    }

    // MARK: - Private Helpers

    private func updateMemoryMetrics() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            memoryMetrics.currentUsage = Int(info.resident_size)
            memoryMetrics.peakUsage = max(memoryMetrics.peakUsage, memoryMetrics.currentUsage)
        }
    }
}

// MARK: - Metrics Structures

struct ImageLoadMetrics: Codable {
    var totalLoads: Int = 0
    var totalDuration: TimeInterval = 0
    var successfulUploads: Int = 0
    var failedUploads: Int = 0

    var averageLoadTime: TimeInterval {
        guard totalLoads > 0 else { return 0 }
        return totalDuration / Double(totalLoads)
    }
}

struct CacheMetrics: Codable {
    var hits: Int = 0
    var misses: Int = 0

    var hitRate: Double {
        let total = hits + misses
        guard total > 0 else { return 0 }
        return Double(hits) / Double(total)
    }

    var totalRequests: Int {
        hits + misses
    }
}

struct NetworkMetrics: Codable {
    var totalBytesDownloaded: Int = 0
    var totalBytesUploaded: Int = 0

    var totalTraffic: Int {
        totalBytesDownloaded + totalBytesUploaded
    }

    var downloadedMB: Double {
        Double(totalBytesDownloaded) / 1024 / 1024
    }

    var uploadedMB: Double {
        Double(totalBytesUploaded) / 1024 / 1024
    }
}

struct MemoryMetrics: Codable {
    var currentUsage: Int = 0
    var peakUsage: Int = 0

    var currentUsageMB: Double {
        Double(currentUsage) / 1024 / 1024
    }

    var peakUsageMB: Double {
        Double(peakUsage) / 1024 / 1024
    }
}

// MARK: - Performance Report

struct PerformanceReport: Codable {
    let imageLoad: ImageLoadMetrics
    let cache: CacheMetrics
    let network: NetworkMetrics
    let memory: MemoryMetrics
    let timestamp: Date

    var summary: String {
        """
        === Media Performance Report ===
        Generated: \(timestamp.formatted())

        Image Loading:
        - Total Loads: \(imageLoad.totalLoads)
        - Average Time: \(String(format: "%.2f", imageLoad.averageLoadTime * 1000))ms
        - Successful Uploads: \(imageLoad.successfulUploads)
        - Failed Uploads: \(imageLoad.failedUploads)

        Cache:
        - Hit Rate: \(String(format: "%.1f%%", cache.hitRate * 100))
        - Total Requests: \(cache.totalRequests)
        - Hits: \(cache.hits)
        - Misses: \(cache.misses)

        Network:
        - Downloaded: \(String(format: "%.2f MB", network.downloadedMB))
        - Uploaded: \(String(format: "%.2f MB", network.uploadedMB))
        - Total Traffic: \(String(format: "%.2f MB", Double(network.totalTraffic) / 1024 / 1024))

        Memory:
        - Current Usage: \(String(format: "%.2f MB", memory.currentUsageMB))
        - Peak Usage: \(String(format: "%.2f MB", memory.peakUsageMB))
        """
    }
}

// MARK: - Performance Debug View

struct MediaPerformanceDebugView: View {
    @StateObject private var metrics = MediaMetrics.shared

    var body: some View {
        NavigationView {
            List {
                // Image Loading Section
                Section("Image Loading") {
                    MetricRow(title: "Total Loads", value: "\(metrics.imageLoadMetrics.totalLoads)")
                    MetricRow(
                        title: "Avg Load Time",
                        value: String(format: "%.0fms", metrics.imageLoadMetrics.averageLoadTime * 1000)
                    )
                    MetricRow(
                        title: "Uploads",
                        value: "\(metrics.imageLoadMetrics.successfulUploads) / \(metrics.imageLoadMetrics.failedUploads)"
                    )
                }

                // Cache Section
                Section("Cache") {
                    MetricRow(
                        title: "Hit Rate",
                        value: String(format: "%.1f%%", metrics.cacheMetrics.hitRate * 100),
                        color: metrics.cacheMetrics.hitRate > 0.7 ? .green : .orange
                    )
                    MetricRow(title: "Hits", value: "\(metrics.cacheMetrics.hits)")
                    MetricRow(title: "Misses", value: "\(metrics.cacheMetrics.misses)")
                }

                // Network Section
                Section("Network") {
                    MetricRow(
                        title: "Downloaded",
                        value: String(format: "%.2f MB", metrics.networkMetrics.downloadedMB)
                    )
                    MetricRow(
                        title: "Uploaded",
                        value: String(format: "%.2f MB", metrics.networkMetrics.uploadedMB)
                    )
                }

                // Memory Section
                Section("Memory") {
                    MetricRow(
                        title: "Current",
                        value: String(format: "%.2f MB", metrics.memoryMetrics.currentUsageMB)
                    )
                    MetricRow(
                        title: "Peak",
                        value: String(format: "%.2f MB", metrics.memoryMetrics.peakUsageMB),
                        color: metrics.memoryMetrics.peakUsageMB > 100 ? .red : .green
                    )
                }

                // Actions
                Section {
                    Button("Export Report") {
                        exportReport()
                    }

                    Button("Reset Metrics") {
                        metrics.reset()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Media Metrics")
            .onAppear {
                metrics.startMonitoring()
            }
            .onDisappear {
                metrics.stopMonitoring()
            }
        }
    }

    private func exportReport() {
        let report = metrics.getPerformanceReport()
        print(report.summary)
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(color)
                .bold()
        }
    }
}

// MARK: - Preview

#Preview {
    MediaPerformanceDebugView()
}
