import Foundation

/// 数字格式化器 - 根据当前语言自动调整数字格式
enum NumberFormatters {
    // MARK: - Number Formatters

    /// 标准数字格式（如：1,234,567）
    static var standard: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter
    }

    /// 货币格式（如：¥1,234.56 / $1,234.56）
    static func currency(currencyCode: String = "USD") -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter
    }

    /// 百分比格式（如：75%）
    static var percent: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }

    /// 序数格式（如：1st, 2nd, 3rd）
    static var ordinal: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.numberStyle = .ordinal
        return formatter
    }

    /// 拼写格式（如：one thousand two hundred thirty-four）
    static var spellOut: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.numberStyle = .spellOut
        return formatter
    }

    // MARK: - Custom Formatters

    /// 紧凑数字格式（如：1.2K, 3.4M）
    static var compact: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter
    }

    /// 格式化为紧凑字符串（1234 -> 1.2K）
    static func compactString(from number: Int) -> String {
        let absNumber = abs(number)
        let sign = number < 0 ? "-" : ""

        switch absNumber {
        case 0..<1000:
            return "\(sign)\(absNumber)"
        case 1000..<1_000_000:
            let value = Double(absNumber) / 1000.0
            return "\(sign)\(String(format: "%.1f", value))K"
        case 1_000_000..<1_000_000_000:
            let value = Double(absNumber) / 1_000_000.0
            return "\(sign)\(String(format: "%.1f", value))M"
        default:
            let value = Double(absNumber) / 1_000_000_000.0
            return "\(sign)\(String(format: "%.1f", value))B"
        }
    }

    /// 文件大小格式化（如：1.2 MB）
    static func fileSize(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 持续时间格式化（如：1:23:45）
    static func duration(seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        return formatter.string(from: seconds) ?? "00:00"
    }

    /// 电话号码格式化（简化版）
    static func phoneNumber(_ number: String) -> String {
        let cleaned = number.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

        // 中国手机号格式：138 1234 5678
        if cleaned.count == 11 && LocalizationManager.shared.currentLanguage == .chineseSimplified {
            let index1 = cleaned.index(cleaned.startIndex, offsetBy: 3)
            let index2 = cleaned.index(cleaned.startIndex, offsetBy: 7)
            return "\(cleaned[..<index1]) \(cleaned[index1..<index2]) \(cleaned[index2...])"
        }

        // 美国电话号格式：(123) 456-7890
        if cleaned.count == 10 && LocalizationManager.shared.currentLanguage == .english {
            let areaCode = cleaned.prefix(3)
            let middle = cleaned.dropFirst(3).prefix(3)
            let last = cleaned.suffix(4)
            return "(\(areaCode)) \(middle)-\(last)"
        }

        return number
    }
}

// MARK: - Int Extension for Convenience

extension Int {
    /// 转换为标准数字字符串
    var standardString: String {
        NumberFormatters.standard.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// 转换为紧凑字符串
    var compactString: String {
        NumberFormatters.compactString(from: self)
    }

    /// 转换为序数字符串
    var ordinalString: String {
        NumberFormatters.ordinal.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// 转换为拼写字符串
    var spellOutString: String {
        NumberFormatters.spellOut.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

// MARK: - Double Extension for Convenience

extension Double {
    /// 转换为标准数字字符串
    var standardString: String {
        NumberFormatters.standard.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// 转换为百分比字符串
    var percentString: String {
        NumberFormatters.percent.string(from: NSNumber(value: self)) ?? "\(self * 100)%"
    }

    /// 转换为货币字符串
    func currencyString(code: String = "USD") -> String {
        NumberFormatters.currency(currencyCode: code).string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

// MARK: - Measurement Formatters

extension NumberFormatters {
    /// 温度格式化
    static func temperature(_ celsius: Double) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let formatter = MeasurementFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.numberFormatter.maximumFractionDigits = 1

        // 中文用摄氏度，英文根据地区选择
        if LocalizationManager.shared.currentLanguage == .english {
            formatter.unitOptions = .providedUnit
            let fahrenheit = measurement.converted(to: .fahrenheit)
            return formatter.string(from: fahrenheit)
        } else {
            return formatter.string(from: measurement)
        }
    }

    /// 距离格式化
    static func distance(meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1

        // 英文使用英里，中文使用公里
        if LocalizationManager.shared.currentLanguage == .english {
            let miles = measurement.converted(to: .miles)
            return formatter.string(from: miles)
        } else {
            return formatter.string(from: measurement)
        }
    }
}
