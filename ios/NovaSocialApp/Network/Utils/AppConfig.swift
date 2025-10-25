import Foundation

/// AppConfig - 应用配置
/// 环境配置、Feature Flags
enum Environment {
    case development
    case staging
    case production

    static var current: Environment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }

    var baseURL: URL {
        switch self {
        case .development:
            // Read from Info.plist, environment variable, or default to localhost
            if let customURL = ProcessInfo.processInfo.environment["API_BASE_URL"],
               let url = URL(string: customURL) {
                return url
            }

            // Try reading from Info.plist
            if let plistURL = Bundle.main.infoDictionary?["API_BASE_URL"] as? String,
               let url = URL(string: plistURL) {
                return url
            }

            // Default to localhost (works on simulator and with port forwarding)
            return URL(string: "http://localhost:8080")!

        case .staging:
            return URL(string: "https://api-staging.nova.social")!
        case .production:
            return URL(string: "https://api.nova.social")!
        }
    }

    var timeout: TimeInterval {
        return 30 // 30 seconds
    }
}

struct AppConfig {
    static var baseURL: URL {
        Environment.current.baseURL
    }

    static var timeout: TimeInterval {
        Environment.current.timeout
    }

    // Messaging WebSocket base URL (without path)
    // Development uses local messaging-service exposed at 8085 (see docker-compose)
    static var messagingWebSocketBaseURL: URL {
        switch Environment.current {
        case .development:
            // Read from environment or use localhost
            if let customURL = ProcessInfo.processInfo.environment["WS_BASE_URL"],
               let url = URL(string: customURL) {
                return url
            }

            // Try reading from Info.plist
            if let plistURL = Bundle.main.infoDictionary?["WS_BASE_URL"] as? String,
               let url = URL(string: plistURL) {
                return url
            }

            return URL(string: "ws://localhost:8085")!

        case .staging, .production:
            // If you have a gateway, set to wss://api.nova.social or dedicated WS endpoint
            return URL(string: "wss://api.nova.social")!
        }
    }
}

// MARK: - Feature Flags

struct FeatureFlags {
    /// 是否启用离线模式
    static let enableOfflineMode = true

    /// 是否启用后台上传
    static let enableBackgroundUpload = true

    /// 是否启用图片压缩
    static let enableImageCompression = true

    /// 最大重试次数
    static let maxRetryAttempts = 3

    /// Feed 每页加载数量
    static let feedPageSize = 20

    /// 图片缓存大小（100MB）
    static let imageCacheSize = 100 * 1024 * 1024

    /// Token 刷新提前时间（60秒）
    static let tokenRefreshBuffer: TimeInterval = 60

    /// 日志级别
    static let logLevel: LogLevel = .debug
}
