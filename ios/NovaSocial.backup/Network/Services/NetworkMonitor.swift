import Foundation
import Network

/// 网络状态监听器 - 监听网络连接变化
@available(iOS 12.0, *)
final class NetworkMonitor {
    // MARK: - Shared Instance

    static let shared = NetworkMonitor()

    // MARK: - Properties

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.nova.network.monitor")

    private(set) var isConnected = false
    private(set) var connectionType: ConnectionType = .unknown

    // MARK: - Callbacks

    var onConnectionChanged: ((Bool, ConnectionType) -> Void)?

    // MARK: - Initialization

    private init() {
        startMonitoring()
    }

    // MARK: - Public API

    /// 开始监听网络状态
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let wasConnected = self.isConnected
            self.isConnected = path.status == .satisfied
            self.connectionType = ConnectionType(path: path)

            // 状态变化时触发回调
            if wasConnected != self.isConnected {
                DispatchQueue.main.async {
                    Logger.log("📡 Network status changed: \(self.isConnected ? "Connected" : "Disconnected") (\(self.connectionType))", level: .info)
                    self.onConnectionChanged?(self.isConnected, self.connectionType)
                }
            }
        }

        monitor.start(queue: queue)
        Logger.log("📡 NetworkMonitor started", level: .info)
    }

    /// 停止监听
    func stopMonitoring() {
        monitor.cancel()
        Logger.log("📡 NetworkMonitor stopped", level: .info)
    }

    deinit {
        stopMonitoring()
    }
}

// MARK: - Connection Type

enum ConnectionType: String {
    case wifi = "WiFi"
    case cellular = "Cellular"
    case wired = "Wired"
    case unknown = "Unknown"

    init(path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            self = .wifi
        } else if path.usesInterfaceType(.cellular) {
            self = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            self = .wired
        } else {
            self = .unknown
        }
    }
}

// MARK: - Retry Manager

/// 网络恢复后自动重试管理器
final class RetryManager {
    // MARK: - Properties

    private var pendingRetries: [String: () async throws -> Void] = [:]
    private let monitor: NetworkMonitor

    // MARK: - Initialization

    init(monitor: NetworkMonitor = .shared) {
        self.monitor = monitor

        // 监听网络恢复
        monitor.onConnectionChanged = { [weak self] isConnected, _ in
            if isConnected {
                self?.retryPendingRequests()
            }
        }
    }

    // MARK: - Public API

    /// 添加待重试的请求
    func addPendingRetry(key: String, retry: @escaping () async throws -> Void) {
        pendingRetries[key] = retry
        Logger.log("🔄 Added pending retry: \(key)", level: .debug)
    }

    /// 移除待重试的请求
    func removePendingRetry(key: String) {
        pendingRetries.removeValue(forKey: key)
    }

    /// 清空所有待重试请求
    func clearPendingRetries() {
        pendingRetries.removeAll()
    }

    // MARK: - Private Helpers

    private func retryPendingRequests() {
        guard !pendingRetries.isEmpty else { return }

        Logger.log("🔄 Network recovered, retrying \(pendingRetries.count) pending requests", level: .info)

        let retries = pendingRetries
        pendingRetries.removeAll()

        // 异步执行所有重试
        Task {
            for (key, retry) in retries {
                do {
                    try await retry()
                    Logger.log("✅ Retry succeeded: \(key)", level: .info)
                } catch {
                    Logger.log("❌ Retry failed: \(key) - \(error)", level: .error)
                }
            }
        }
    }
}
