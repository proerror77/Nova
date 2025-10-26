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
            // iOS Simulator: Use host's actual IP address
            // The simulator cannot access localhost/127.0.0.1 on the host machine
            // Mac IP: 192.168.31.127, API Gateway runs on port 3000
            #if targetEnvironment(simulator)
            return URL(string: "http://192.168.31.127:3000")!  // API Gateway port
            #else
            return URL(string: "http://localhost:8080")!
            #endif
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
    // Development uses local messaging-service exposed via API Gateway
    static var messagingWebSocketBaseURL: URL {
        switch Environment.current {
        case .development:
            // iOS Simulator: messaging-service is exposed via API Gateway at port 3000
            // WebSocket path: /ws (configured in nginx)
            // Use host's actual IP address (192.168.31.127)
            #if targetEnvironment(simulator)
            return URL(string: "ws://192.168.31.127:3000")!
            #else
            return URL(string: "ws://localhost:8085")!
            #endif
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

    /// 是否允許將非 UUID 的使用者 ID 做本地映射（開發/測試用）
    /// true: 允許將任意字串穩定映射為 UUID（透過哈希）
    /// false: 僅接受合法 UUID（預設上線請關閉）
    static let enableNonUUIDUserIdMapping: Bool = true

    /// 嚴格 E2E 模式（客戶端加密）。開啟後，發送時會使用 CryptoCore 加密，payload 以 "ENC:v1:<nonce_b64>:<ciphertext_b64>" 形式傳遞
    /// 後端可當作不透明字串存儲。接收端可在客戶端解密（需要對方公鑰）。
    static let enableStrictE2E: Bool = true
}
