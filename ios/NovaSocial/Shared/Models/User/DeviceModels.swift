import Foundation

// MARK: - Device Models
// 设备管理相关数据模型，用于显示和管理用户的登录设备

/// 设备类型枚举
enum DeviceType: String, Codable {
    case ios = "iOS"
    case macos = "macOS"
    case android = "Android"
    case web = "Web"
    case unknown = "Unknown"

    /// 获取设备图标名称 (SF Symbols)
    var iconName: String {
        switch self {
        case .ios:
            return "iphone"
        case .macos:
            return "desktopcomputer"
        case .android:
            return "phone.fill"
        case .web:
            return "globe"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

/// 设备信息模型
struct Device: Codable, Identifiable {
    let id: String
    let userId: String
    let deviceType: DeviceType
    let deviceName: String
    let deviceModel: String?
    let osVersion: String?
    let appVersion: String?
    let lastActiveAt: Int64?
    let createdAt: Int64
    let isCurrent: Bool?

    /// 格式化的最后活跃时间
    var formattedLastActive: String {
        guard let lastActiveAt = lastActiveAt else {
            return "Invalid Date"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(lastActiveAt) / 1000.0)
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute], from: date, to: now)

        if let days = components.day, days > 0 {
            if days == 1 {
                return "1 day ago"
            } else if days < 7 {
                return "\(days) days ago"
            } else if days < 30 {
                let weeks = days / 7
                return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
            } else if days < 365 {
                let months = days / 30
                return months == 1 ? "1 month ago" : "\(months) months ago"
            } else {
                let years = days / 365
                return years == 1 ? "1 year ago" : "\(years) years ago"
            }
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "Just now"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case deviceType = "device_type"
        case deviceName = "device_name"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case appVersion = "app_version"
        case lastActiveAt = "last_active_at"
        case createdAt = "created_at"
        case isCurrent = "is_current"
    }
}

// MARK: - API Response Models

/// 设备列表响应
struct GetDevicesResponse: Codable {
    let devices: [Device]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case devices
        case total
    }
}

/// 当前设备响应
struct GetCurrentDeviceResponse: Codable {
    let device: Device
}

/// 登出设备请求
struct LogoutDeviceRequest: Codable {
    let deviceId: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
    }
}

/// 登出设备响应
struct LogoutDeviceResponse: Codable {
    let success: Bool
    let message: String?
}
