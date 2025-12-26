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
    let deviceType: DeviceType
    let deviceName: String
    let osVersion: String?
    let lastActiveAt: Int64?
    let isCurrent: Bool?
    
    // Optional fields (may not be in backend response)
    let deviceModel: String?
    let appVersion: String?
    let createdAt: Int64?

    /// 格式化的最後活躍時間
    var formattedLastActive: String {
        guard let lastActiveAt = lastActiveAt else {
            return "Unknown"
        }

        // Backend returns seconds, convert to Date
        let date = Date(timeIntervalSince1970: TimeInterval(lastActiveAt))
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
        case deviceType = "device_type"
        case deviceName = "name"
        case osVersion = "os"
        case lastActiveAt = "last_active"
        case isCurrent = "is_current"
        // Optional fields with snake_case mapping
        case deviceModel = "device_model"
        case appVersion = "app_version"
        case createdAt = "created_at"
    }
    
    // Custom initializer for creating local device
    init(id: String, deviceType: DeviceType, deviceName: String, osVersion: String?, lastActiveAt: Int64?, isCurrent: Bool?, deviceModel: String? = nil, appVersion: String? = nil, createdAt: Int64? = nil) {
        self.id = id
        self.deviceType = deviceType
        self.deviceName = deviceName
        self.osVersion = osVersion
        self.lastActiveAt = lastActiveAt
        self.isCurrent = isCurrent
        self.deviceModel = deviceModel
        self.appVersion = appVersion
        self.createdAt = createdAt
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
