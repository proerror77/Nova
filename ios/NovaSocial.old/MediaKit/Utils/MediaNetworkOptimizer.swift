import Network
import UIKit

/// 媒体网络优化器 - 基于网络状态智能调整质量
///
/// Linus 风格：简单的状态机，清晰的策略
/// - WiFi: 高清
/// - 蜂窝: 标清
/// - 低速网络: 缩略图
@MainActor
final class MediaNetworkOptimizer: ObservableObject {
    static let shared = MediaNetworkOptimizer()

    // MARK: - Published Properties

    @Published private(set) var networkStatus: NetworkStatus = .unknown
    @Published private(set) var imageQuality: ImageQualityLevel = .high
    @Published private(set) var videoQuality: VideoQualityLevel = .high

    // MARK: - Private Properties

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.nova.network-monitor")

    // MARK: - Initialization

    init() {
        startMonitoring()
    }

    // MARK: - Public API

    /// 获取适合当前网络的图片 URL
    /// - Parameter baseURL: 基础 URL
    /// - Returns: 优化后的 URL
    func optimizedImageURL(for baseURL: String) -> String {
        switch imageQuality {
        case .high:
            return baseURL
        case .medium:
            return appendQualityParam(baseURL, quality: "medium")
        case .low:
            return appendQualityParam(baseURL, quality: "thumbnail")
        }
    }

    /// 是否应该预加载
    var shouldPrefetch: Bool {
        networkStatus == .wifi
    }

    /// 是否应该自动播放视频
    var shouldAutoPlayVideo: Bool {
        networkStatus == .wifi
    }

    /// 获取推荐的图片压缩质量
    var recommendedCompressionQuality: CGFloat {
        switch networkStatus {
        case .wifi:
            return 0.9
        case .cellular:
            return 0.7
        case .lowDataMode:
            return 0.5
        case .unknown:
            return 0.8
        }
    }

    // MARK: - Private Helpers

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.updateNetworkStatus(path)
            }
        }
        monitor.start(queue: queue)
    }

    private func updateNetworkStatus(_ path: NWPath) {
        // 检测网络类型
        if path.usesInterfaceType(.wifi) {
            networkStatus = .wifi
            imageQuality = .high
            videoQuality = .high
        } else if path.usesInterfaceType(.cellular) {
            if path.isConstrained {
                networkStatus = .lowDataMode
                imageQuality = .low
                videoQuality = .low
            } else {
                networkStatus = .cellular
                imageQuality = .medium
                videoQuality = .medium
            }
        } else {
            networkStatus = .unknown
            imageQuality = .medium
            videoQuality = .medium
        }
    }

    private func appendQualityParam(_ url: String, quality: String) -> String {
        guard var components = URLComponents(string: url) else { return url }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "quality", value: quality))
        components.queryItems = queryItems

        return components.url?.absoluteString ?? url
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - Network Status

enum NetworkStatus {
    case wifi
    case cellular
    case lowDataMode
    case unknown

    var description: String {
        switch self {
        case .wifi: return "WiFi"
        case .cellular: return "Cellular"
        case .lowDataMode: return "Low Data Mode"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Quality Levels

enum ImageQualityLevel {
    case high
    case medium
    case low
}

enum VideoQualityLevel {
    case high
    case medium
    case low

    var preset: String {
        switch self {
        case .high:
            return "1080p"
        case .medium:
            return "720p"
        case .low:
            return "480p"
        }
    }
}
