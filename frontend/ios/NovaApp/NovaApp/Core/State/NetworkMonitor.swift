import Foundation
import Network
import Combine

/// Network connectivity monitor
/// Tracks online/offline state and connection quality
@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected: Bool = true
    @Published var quality: NetworkQuality = .good

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        startMonitoring()
    }

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.quality = self?.determineQuality(from: path) ?? .none
            }
        }
        monitor.start(queue: queue)
    }

    private func determineQuality(from path: NWPath) -> NetworkQuality {
        if path.status != .satisfied {
            return .none
        }

        if path.usesInterfaceType(.wifi) {
            return .excellent
        } else if path.usesInterfaceType(.cellular) {
            // Simplified: assume 4G+ for cellular
            return .good
        } else {
            return .poor
        }
    }

    deinit {
        monitor.cancel()
    }
}
