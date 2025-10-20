import Foundation
import UIKit
import SwiftUI

/// 实时性能监控器
///
/// 监控指标：
/// - FPS（帧率）
/// - 内存使用
/// - CPU 使用率
/// - 网络延迟
/// - 启动时间
@MainActor
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()

    // MARK: - Published Metrics
    @Published var currentFPS: Int = 60
    @Published var memoryUsageMB: Double = 0
    @Published var cpuUsagePercent: Double = 0
    @Published var isMonitoring = false

    // MARK: - Performance Logs
    private(set) var performanceLogs: [PerformanceLog] = []

    struct PerformanceLog {
        let timestamp: Date
        let fps: Int
        let memoryMB: Double
        let cpuPercent: Double
        let event: String?
    }

    // MARK: - FPS Tracking
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var frameCount = 0

    // MARK: - Startup Time
    private(set) var appLaunchTime: Date?
    private(set) var firstFrameTime: Date?
    private(set) var timeToInteractive: TimeInterval?

    var startupTime: TimeInterval? {
        guard let launch = appLaunchTime, let firstFrame = firstFrameTime else {
            return nil
        }
        return firstFrame.timeIntervalSince(launch)
    }

    // MARK: - Initialization
    private init() {
        appLaunchTime = Date()
    }

    // MARK: - Public API

    /// 开始监控
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true

        // FPS 监控
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        displayLink?.add(to: .main, forMode: .common)

        // 内存和 CPU 监控（每秒更新）
        Task {
            while isMonitoring {
                updateMemoryUsage()
                updateCPUUsage()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }

        print("✅ Performance monitoring started")
    }

    /// 停止监控
    func stopMonitoring() {
        isMonitoring = false
        displayLink?.invalidate()
        displayLink = nil
        print("⏹️ Performance monitoring stopped")
    }

    /// 记录性能事件
    func logEvent(_ event: String) {
        let log = PerformanceLog(
            timestamp: Date(),
            fps: currentFPS,
            memoryMB: memoryUsageMB,
            cpuPercent: cpuUsagePercent,
            event: event
        )
        performanceLogs.append(log)

        // 保留最近 100 条日志
        if performanceLogs.count > 100 {
            performanceLogs.removeFirst()
        }

        print("📊 Performance Event: \(event) | FPS: \(currentFPS) | Memory: \(String(format: "%.1f", memoryUsageMB))MB | CPU: \(String(format: "%.1f", cpuUsagePercent))%")
    }

    /// 标记首帧渲染
    func markFirstFrame() {
        guard firstFrameTime == nil else { return }
        firstFrameTime = Date()

        if let startup = startupTime {
            print("🚀 App startup time: \(String(format: "%.2f", startup))s")
        }
    }

    /// 标记交互就绪
    func markTimeToInteractive() {
        guard let launch = appLaunchTime else { return }
        timeToInteractive = Date().timeIntervalSince(launch)
        print("⚡ Time to interactive: \(String(format: "%.2f", timeToInteractive!))s")
    }

    /// 导出性能报告
    func generateReport() -> PerformanceReport {
        let avgFPS = performanceLogs.isEmpty ? 0 : performanceLogs.map(\.fps).reduce(0, +) / performanceLogs.count
        let avgMemory = performanceLogs.isEmpty ? 0 : performanceLogs.map(\.memoryMB).reduce(0, +) / Double(performanceLogs.count)
        let avgCPU = performanceLogs.isEmpty ? 0 : performanceLogs.map(\.cpuPercent).reduce(0, +) / Double(performanceLogs.count)

        return PerformanceReport(
            startupTime: startupTime,
            timeToInteractive: timeToInteractive,
            averageFPS: avgFPS,
            averageMemoryMB: avgMemory,
            averageCPUPercent: avgCPU,
            peakMemoryMB: performanceLogs.map(\.memoryMB).max() ?? 0,
            logsCount: performanceLogs.count
        )
    }

    // MARK: - Private Helpers

    @objc private func displayLinkTick() {
        let timestamp = displayLink?.timestamp ?? 0

        if lastFrameTimestamp == 0 {
            lastFrameTimestamp = timestamp
            return
        }

        frameCount += 1

        let elapsed = timestamp - lastFrameTimestamp

        // 每秒更新 FPS
        if elapsed >= 1.0 {
            currentFPS = frameCount
            frameCount = 0
            lastFrameTimestamp = timestamp
        }
    }

    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        if kerr == KERN_SUCCESS {
            memoryUsageMB = Double(info.resident_size) / 1024.0 / 1024.0
        }
    }

    private func updateCPUUsage() {
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = task_threads(mach_task_self_, &threadsList, &threadsCount)

        guard threadsResult == KERN_SUCCESS, let threads = threadsList else {
            return
        }

        var totalCPU: Double = 0

        for index in 0..<Int(threadsCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

            let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(
                        threads[index],
                        thread_flavor_t(THREAD_BASIC_INFO),
                        $0,
                        &threadInfoCount
                    )
                }
            }

            guard infoResult == KERN_SUCCESS else {
                continue
            }

            if threadInfo.flags & TH_FLAGS_IDLE == 0 {
                totalCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }

        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: threads)),
            vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride)
        )

        cpuUsagePercent = totalCPU
    }
}

// MARK: - Performance Report
struct PerformanceReport {
    let startupTime: TimeInterval?
    let timeToInteractive: TimeInterval?
    let averageFPS: Int
    let averageMemoryMB: Double
    let averageCPUPercent: Double
    let peakMemoryMB: Double
    let logsCount: Int

    var summary: String {
        """
        📊 Performance Report
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        🚀 Startup Time: \(startupTime.map { String(format: "%.2fs", $0) } ?? "N/A")
        ⚡ Time to Interactive: \(timeToInteractive.map { String(format: "%.2fs", $0) } ?? "N/A")
        🎬 Average FPS: \(averageFPS)
        💾 Average Memory: \(String(format: "%.1fMB", averageMemoryMB))
        🔥 Peak Memory: \(String(format: "%.1fMB", peakMemoryMB))
        ⚙️  Average CPU: \(String(format: "%.1f%%", averageCPUPercent))
        📝 Logs Collected: \(logsCount)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        """
    }

    var isHealthy: Bool {
        averageFPS >= 55 &&          // 至少 55 FPS
        averageMemoryMB < 200 &&     // 平均内存 < 200MB
        peakMemoryMB < 300 &&        // 峰值内存 < 300MB
        (startupTime ?? 5) < 2.0     // 启动时间 < 2s
    }
}

// MARK: - SwiftUI Performance Overlay
struct PerformanceOverlay: View {
    @StateObject private var monitor = PerformanceMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("FPS:")
                    .font(.system(size: 10, weight: .bold))
                Text("\(monitor.currentFPS)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(fpsColor)
            }

            HStack(spacing: 8) {
                Text("Mem:")
                    .font(.system(size: 10, weight: .bold))
                Text(String(format: "%.1fMB", monitor.memoryUsageMB))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(memoryColor)
            }

            HStack(spacing: 8) {
                Text("CPU:")
                    .font(.system(size: 10, weight: .bold))
                Text(String(format: "%.1f%%", monitor.cpuUsagePercent))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(cpuColor)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
        .foregroundColor(.white)
        .onAppear {
            monitor.startMonitoring()
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
    }

    private var fpsColor: Color {
        switch monitor.currentFPS {
        case 55...60: return .green
        case 30..<55: return .yellow
        default: return .red
        }
    }

    private var memoryColor: Color {
        switch monitor.memoryUsageMB {
        case 0..<150: return .green
        case 150..<250: return .yellow
        default: return .red
        }
    }

    private var cpuColor: Color {
        switch monitor.cpuUsagePercent {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }
}

// MARK: - View Extension
extension View {
    func performanceOverlay(enabled: Bool = true) -> some View {
        ZStack(alignment: .topTrailing) {
            self

            if enabled {
                PerformanceOverlay()
                    .padding()
            }
        }
    }
}
