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
        // 优先使用 Info.plist 中的覆盖值（键：API_BASE_URL），便于真机调试改为局域网 IP
        if let override = Bundle.main.infoDictionary?["API_BASE_URL"] as? String,
           let url = URL(string: override), !override.isEmpty {
            return url
        }

        switch self {
        case .development:
            // iOS 模拟器 → 访问宿主机服务请使用 localhost
            // 后端本地端口（.env 中 USER_SERVICE_PORT=8085）
            return URL(string: "http://localhost:8085")!
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
