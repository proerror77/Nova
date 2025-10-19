import Foundation

/// Provides locale-aware formatters for dates, numbers, and currencies
final class LocalizedFormatters {

    // MARK: - Singleton
    static let shared = LocalizedFormatters()

    // MARK: - Private Properties
    private var currentLocale: Locale {
        LocalizationManager.shared.currentLocale
    }

    private init() {
        // Listen for language changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .languageDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func languageDidChange() {
        // Clear cached formatters when language changes
        _dateFormatter = nil
        _timeFormatter = nil
        _dateTimeFormatter = nil
        _relativeDateFormatter = nil
        _numberFormatter = nil
        _currencyFormatter = nil
        _percentFormatter = nil
        _compactNumberFormatter = nil
    }

    // MARK: - Date Formatters

    private var _dateFormatter: DateFormatter?
    /// Formatter for dates (e.g., "Jan 15, 2025" or "2025年1月15日")
    var dateFormatter: DateFormatter {
        if let formatter = _dateFormatter {
            return formatter
        }
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        _dateFormatter = formatter
        return formatter
    }

    private var _timeFormatter: DateFormatter?
    /// Formatter for times (e.g., "3:45 PM" or "15:45")
    var timeFormatter: DateFormatter {
        if let formatter = _timeFormatter {
            return formatter
        }
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        _timeFormatter = formatter
        return formatter
    }

    private var _dateTimeFormatter: DateFormatter?
    /// Formatter for date and time (e.g., "Jan 15, 2025 at 3:45 PM")
    var dateTimeFormatter: DateFormatter {
        if let formatter = _dateTimeFormatter {
            return formatter
        }
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        _dateTimeFormatter = formatter
        return formatter
    }

    private var _relativeDateFormatter: RelativeDateTimeFormatter?
    /// Formatter for relative dates (e.g., "2 hours ago", "yesterday")
    var relativeDateFormatter: RelativeDateTimeFormatter {
        if let formatter = _relativeDateFormatter {
            return formatter
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = currentLocale
        formatter.unitsStyle = .full
        _relativeDateFormatter = formatter
        return formatter
    }

    // MARK: - Number Formatters

    private var _numberFormatter: NumberFormatter?
    /// Formatter for numbers with locale-specific separators
    var numberFormatter: NumberFormatter {
        if let formatter = _numberFormatter {
            return formatter
        }
        let formatter = NumberFormatter()
        formatter.locale = currentLocale
        formatter.numberStyle = .decimal
        _numberFormatter = formatter
        return formatter
    }

    private var _currencyFormatter: NumberFormatter?
    /// Formatter for currency values
    var currencyFormatter: NumberFormatter {
        if let formatter = _currencyFormatter {
            return formatter
        }
        let formatter = NumberFormatter()
        formatter.locale = currentLocale
        formatter.numberStyle = .currency
        _currencyFormatter = formatter
        return formatter
    }

    private var _percentFormatter: NumberFormatter?
    /// Formatter for percentages
    var percentFormatter: NumberFormatter {
        if let formatter = _percentFormatter {
            return formatter
        }
        let formatter = NumberFormatter()
        formatter.locale = currentLocale
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        _percentFormatter = formatter
        return formatter
    }

    private var _compactNumberFormatter: NumberFormatter?
    /// Formatter for compact numbers (e.g., "1.2K", "3.5M")
    var compactNumberFormatter: NumberFormatter {
        if let formatter = _compactNumberFormatter {
            return formatter
        }
        let formatter = NumberFormatter()
        formatter.locale = currentLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        _compactNumberFormatter = formatter
        return formatter
    }

    // MARK: - Custom Formatters

    /// Format a date as a custom pattern
    func formatDate(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Format a relative time (e.g., "2 minutes ago")
    func formatRelativeTime(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        // Just now (< 1 minute)
        if interval < 60 {
            return L10n.Time.justNow.localized
        }

        // Minutes ago
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return L10n.Time.minuteAgo(minutes)
        }

        // Hours ago
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return L10n.Time.hourAgo(hours)
        }

        // Days ago
        if interval < 604800 {
            let days = Int(interval / 86400)
            return L10n.Time.dayAgo(days)
        }

        // Weeks ago
        if interval < 2592000 {
            let weeks = Int(interval / 604800)
            return L10n.Time.weekAgo(weeks)
        }

        // Fallback to date formatter
        return dateFormatter.string(from: date)
    }

    /// Format a number with compact notation (K, M, B)
    func formatCompactNumber(_ number: Int) -> String {
        let abs = Double(abs(number))
        let sign = number < 0 ? "-" : ""

        switch abs {
        case 0..<1_000:
            return "\(sign)\(number)"
        case 1_000..<1_000_000:
            let value = abs / 1_000
            return "\(sign)\(String(format: "%.1f", value))K"
        case 1_000_000..<1_000_000_000:
            let value = abs / 1_000_000
            return "\(sign)\(String(format: "%.1f", value))M"
        default:
            let value = abs / 1_000_000_000
            return "\(sign)\(String(format: "%.1f", value))B"
        }
    }

    /// Format bytes to human-readable format
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Format phone number based on locale
    func formatPhoneNumber(_ phoneNumber: String) -> String {
        // Remove all non-numeric characters
        let cleaned = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

        // Apply locale-specific formatting
        let locale = currentLocale
        let regionCode = locale.region?.identifier ?? "US"

        switch regionCode {
        case "CN", "TW", "HK":
            // Chinese format: +86 138 0000 0000
            if cleaned.count == 11 {
                let prefix = String(cleaned.prefix(3))
                let middle = String(cleaned.dropFirst(3).prefix(4))
                let suffix = String(cleaned.suffix(4))
                return "\(prefix) \(middle) \(suffix)"
            }
        case "JP":
            // Japanese format: 090-0000-0000
            if cleaned.count == 11 {
                let prefix = String(cleaned.prefix(3))
                let middle = String(cleaned.dropFirst(3).prefix(4))
                let suffix = String(cleaned.suffix(4))
                return "\(prefix)-\(middle)-\(suffix)"
            }
        case "US":
            // US format: (555) 123-4567
            if cleaned.count == 10 {
                let area = String(cleaned.prefix(3))
                let prefix = String(cleaned.dropFirst(3).prefix(3))
                let suffix = String(cleaned.suffix(4))
                return "(\(area)) \(prefix)-\(suffix)"
            }
        default:
            break
        }

        return phoneNumber
    }

    /// Format address based on locale
    func formatAddress(street: String, city: String, state: String?, postalCode: String, country: String) -> String {
        let locale = currentLocale
        let regionCode = locale.region?.identifier ?? "US"

        switch regionCode {
        case "CN":
            // Chinese format: Country PostalCode State City Street
            return "\(country) \(postalCode) \(state ?? "") \(city) \(street)"
        case "JP":
            // Japanese format: PostalCode Country State City Street
            return "〒\(postalCode) \(country) \(state ?? "") \(city) \(street)"
        default:
            // Western format: Street, City, State PostalCode, Country
            let statePart = state.map { ", \($0)" } ?? ""
            return "\(street), \(city)\(statePart) \(postalCode), \(country)"
        }
    }
}

// MARK: - Convenience Extensions

extension Date {
    /// Format as localized date string
    var localizedDate: String {
        LocalizedFormatters.shared.dateFormatter.string(from: self)
    }

    /// Format as localized time string
    var localizedTime: String {
        LocalizedFormatters.shared.timeFormatter.string(from: self)
    }

    /// Format as localized date and time string
    var localizedDateTime: String {
        LocalizedFormatters.shared.dateTimeFormatter.string(from: self)
    }

    /// Format as relative time (e.g., "2 hours ago")
    var relativeTime: String {
        LocalizedFormatters.shared.formatRelativeTime(from: self)
    }
}

extension Int {
    /// Format as localized number
    var localizedNumber: String {
        LocalizedFormatters.shared.numberFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// Format as compact number (e.g., "1.2K")
    var compactNumber: String {
        LocalizedFormatters.shared.formatCompactNumber(self)
    }
}

extension Double {
    /// Format as localized number
    var localizedNumber: String {
        LocalizedFormatters.shared.numberFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// Format as currency
    func localizedCurrency(currencyCode: String? = nil) -> String {
        let formatter = LocalizedFormatters.shared.currencyFormatter
        if let code = currencyCode {
            formatter.currencyCode = code
        }
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// Format as percentage
    var localizedPercent: String {
        LocalizedFormatters.shared.percentFormatter.string(from: NSNumber(value: self)) ?? "\(self)%"
    }
}
