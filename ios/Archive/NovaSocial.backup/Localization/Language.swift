import Foundation

/// 支持的语言枚举
enum Language: String, CaseIterable, Identifiable {
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case english = "en"

    var id: String { rawValue }

    /// 显示名称（本地化）
    var displayName: String {
        switch self {
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        case .english:
            return "English"
        }
    }

    /// 原生名称（始终用该语言显示）
    var nativeName: String {
        switch self {
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        case .english:
            return "English"
        }
    }

    /// Locale 标识符
    var localeIdentifier: String {
        rawValue
    }

    /// 对应的 Locale 对象
    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    /// 从系统语言自动检测
    static func fromSystemLanguage() -> Language {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"

        if preferredLanguage.hasPrefix("zh-Hans") {
            return .chineseSimplified
        } else if preferredLanguage.hasPrefix("zh-Hant") || preferredLanguage.hasPrefix("zh-HK") || preferredLanguage.hasPrefix("zh-TW") {
            return .chineseTraditional
        } else {
            return .english
        }
    }

    /// 从字符串解析语言
    static func from(identifier: String) -> Language? {
        Language.allCases.first { $0.rawValue == identifier }
    }
}
