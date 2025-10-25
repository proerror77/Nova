import Foundation
import Network

/// 网络状态监控
/// 检测网络可用性变化，触发离线队列同步
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected: Bool = true
    @Published var isExpensive: Bool = false

    private let queue = DispatchQueue(label: "com.nova.network-monitor")
    private let monitor: NWPathMonitor
    private var lastConnectedState: Bool = true

    init() {
        monitor = NWPathMonitor()

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasConnected = self?.isConnected ?? true
                let isNowConnected = path.status == .satisfied

                self?.isConnected = isNowConnected
                self?.isExpensive = path.isExpensive

                // 网络从断开到连接，触发离线队列同步
                if !wasConnected && isNowConnected {
                    Task {
                        await self?.syncOfflineMessages()
                    }
                }
            }
        }

        monitor.start(queue: queue)
    }

    // MARK: - Private

    private func syncOfflineMessages() async {
        let repository = MessagingRepository()
        await OfflineMessageQueue.shared.syncPendingMessages(repository: repository)
    }

    deinit {
        monitor.cancel()
    }
}
