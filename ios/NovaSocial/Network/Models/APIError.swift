import Foundation

/// API 错误类型
/// 遵循 Linus 原则：只有 3 类错误 - 网络错误、业务错误、未知错误
enum APIError: Error, LocalizedError {
    // MARK: - 网络层错误
    case networkError(Error)
    case noConnection
    case timeout
    case cancelled

    // MARK: - HTTP 状态码错误
    case unauthorized         // 401
    case forbidden            // 403
    case notFound             // 404
    case conflict             // 409
    case serverError          // 500+

    // MARK: - 业务逻辑错误
    case invalidCredentials
    case emailAlreadyExists
    case usernameAlreadyExists
    case invalidFileFormat
    case fileTooLarge
    case captionTooLong
    case rateLimitExceeded

    // MARK: - 数据解析错误
    case decodingError(Error)
    case invalidResponse

    // MARK: - 未知错误
    case unknown(String)

    // MARK: - 用户友好的错误描述
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "网络连接失败，请检查网络设置"
        case .noConnection:
            return "无网络连接，请检查网络后重试"
        case .timeout:
            return "请求超时，请稍后重试"
        case .cancelled:
            return nil // 用户主动取消，不显示错误
        case .unauthorized:
            return "登录已过期，请重新登录"
        case .forbidden:
            return "没有权限执行此操作"
        case .notFound:
            return "请求的内容不存在"
        case .conflict:
            return "操作冲突，请刷新后重试"
        case .serverError:
            return "服务器错误，请稍后重试"
        case .invalidCredentials:
            return "邮箱或密码错误"
        case .emailAlreadyExists:
            return "该邮箱已被注册"
        case .usernameAlreadyExists:
            return "用户名已被占用"
        case .invalidFileFormat:
            return "不支持的文件格式，请选择 JPG 或 PNG"
        case .fileTooLarge:
            return "文件大小超过限制（最大 10MB）"
        case .captionTooLong:
            return "描述文字过长（最多 300 字符）"
        case .rateLimitExceeded:
            return "操作过于频繁，请稍后再试"
        case .decodingError(let error):
            #if DEBUG
            return "数据解析失败: \(error.localizedDescription)"
            #else
            return "数据解析失败"
            #endif
        case .invalidResponse:
            return "服务器响应格式错误"
        case .unknown(let message):
            return message.isEmpty ? "未知错误" : message
        }
    }

    // MARK: - 从 HTTP 状态码和响应数据构造错误
    static func from(statusCode: Int, data: Data?) -> APIError {
        // 尝试解析后端返回的错误信息
        if let data = data,
           let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return mapBackendError(errorResponse)
        }

        // 根据状态码返回通用错误
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict
        case 429: return .rateLimitExceeded
        case 500...: return .serverError
        default: return .unknown("HTTP \(statusCode)")
        }
    }

    // MARK: - 映射后端错误码到客户端错误
    private static func mapBackendError(_ response: ErrorResponse) -> APIError {
        switch response.code {
        case "INVALID_CREDENTIALS": return .invalidCredentials
        case "EMAIL_EXISTS": return .emailAlreadyExists
        case "USERNAME_EXISTS": return .usernameAlreadyExists
        case "FILE_TOO_LARGE": return .fileTooLarge
        case "INVALID_FORMAT": return .invalidFileFormat
        case "CAPTION_TOO_LONG": return .captionTooLong
        case "RATE_LIMIT_EXCEEDED": return .rateLimitExceeded
        default: return .unknown(response.message)
        }
    }

    // MARK: - 从网络错误构造
    static func from(error: Error) -> APIError {
        let nsError = error as NSError

        // URLSession 错误
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost:
                return .noConnection
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorCancelled:
                return .cancelled
            default:
                return .networkError(error)
            }
        }

        // 其他错误
        return .networkError(error)
    }

    // MARK: - 是否需要重试
    var shouldRetry: Bool {
        switch self {
        case .timeout, .noConnection, .networkError, .serverError:
            return true
        default:
            return false
        }
    }

    // MARK: - 是否需要重新登录
    var requiresReauthentication: Bool {
        if case .unauthorized = self {
            return true
        }
        return false
    }
}
