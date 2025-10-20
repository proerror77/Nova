import Foundation

/// 日期时间格式化器 - 根据当前语言自动调整格式
enum DateTimeFormatters {
    // MARK: - Date Formatters

    /// 完整日期格式（如：2024年1月15日 / January 15, 2024）
    static var fullDate: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }

    /// 短日期格式（如：2024/1/15 / 1/15/24）
    static var shortDate: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }

    /// 中等日期格式（如：2024年1月15日 / Jan 15, 2024）
    static var mediumDate: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    // MARK: - Time Formatters

    /// 完整时间格式（如：下午3:30:00 / 3:30:00 PM）
    static var fullTime: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .long
        return formatter
    }

    /// 短时间格式（如：15:30 / 3:30 PM）
    static var shortTime: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    // MARK: - DateTime Formatters

    /// 完整日期时间格式
    static var fullDateTime: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }

    /// 短日期时间格式
    static var shortDateTime: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    // MARK: - Custom Formatters

    /// ISO 8601 格式（用于 API 通信）
    static var iso8601: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    /// 相对时间格式（如：2小时前 / 2 hours ago）
    static func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// 相对时间格式（缩写）（如：2小时前 / 2h ago）
    static func relativeTimeShort(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// 自定义格式
    static func custom(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - Date Extension for Convenience

extension Date {
    /// 转换为完整日期字符串
    var fullDateString: String {
        DateTimeFormatters.fullDate.string(from: self)
    }

    /// 转换为短日期字符串
    var shortDateString: String {
        DateTimeFormatters.shortDate.string(from: self)
    }

    /// 转换为完整时间字符串
    var fullTimeString: String {
        DateTimeFormatters.fullTime.string(from: self)
    }

    /// 转换为短时间字符串
    var shortTimeString: String {
        DateTimeFormatters.shortTime.string(from: self)
    }

    /// 转换为完整日期时间字符串
    var fullDateTimeString: String {
        DateTimeFormatters.fullDateTime.string(from: self)
    }

    /// 转换为短日期时间字符串
    var shortDateTimeString: String {
        DateTimeFormatters.shortDateTime.string(from: self)
    }

    /// 相对时间字符串
    var relativeTimeString: String {
        DateTimeFormatters.relativeTime(from: self)
    }

    /// 相对时间字符串（缩写）
    var relativeTimeStringShort: String {
        DateTimeFormatters.relativeTimeShort(from: self)
    }

    /// 智能时间显示（今天显示时间，昨天显示"昨天"，更早显示日期）
    var smartTimeString: String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(self) {
            return shortTimeString
        } else if calendar.isDateInYesterday(self) {
            return "昨天".localized + " " + shortTimeString
        } else if calendar.isDate(self, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.locale = LocalizationManager.shared.currentLanguage.locale
            formatter.dateFormat = "EEEE"
            return formatter.string(from: self)
        } else {
            return shortDateString
        }
    }
}
