import Foundation
import SwiftUI
import Combine

/// Supported languages in the app
enum AppLanguage: String, CaseIterable, Identifiable {
    case systemDefault = "system"
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"

    var id: String { rawValue }

    /// Display name for the language
    var displayName: String {
        switch self {
        case .systemDefault:
            return "language.systemDefault".localized
        case .english:
            return "English"
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        case .japanese:
            return "日本語"
        }
    }

    /// Native display name (shown in language selection)
    var nativeDisplayName: String {
        switch self {
        case .systemDefault:
            return NSLocalizedString("language.systemDefault", comment: "")
        case .english:
            return "English"
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        case .japanese:
            return "日本語"
        }
    }

    /// Locale identifier
    var localeIdentifier: String {
        switch self {
        case .systemDefault:
            return Locale.preferredLanguages.first ?? "en"
        case .english:
            return "en"
        case .chineseSimplified:
            return "zh-Hans"
        case .chineseTraditional:
            return "zh-Hant"
        case .japanese:
            return "ja"
        }
    }

    /// Flag emoji for the language
    var flagEmoji: String {
        switch self {
        case .systemDefault:
            return "🌐"
        case .english:
            return "🇺🇸"
        case .chineseSimplified:
            return "🇨🇳"
        case .chineseTraditional:
            return "🇹🇼"
        case .japanese:
            return "🇯🇵"
        }
    }
}

/// Text direction for RTL support
enum TextDirection {
    case leftToRight
    case rightToLeft

    var layoutDirection: LayoutDirection {
        switch self {
        case .leftToRight:
            return .leftToRight
        case .rightToLeft:
            return .rightToLeft
        }
    }
}

/// Manages app localization and language switching
@MainActor
final class LocalizationManager: ObservableObject {

    // MARK: - Singleton
    static let shared = LocalizationManager()

    // MARK: - Published Properties
    @Published private(set) var currentLanguage: AppLanguage
    @Published private(set) var currentLocale: Locale
    @Published private(set) var textDirection: TextDirection

    // MARK: - Private Properties
    private let userDefaultsKey = "AppLanguage"
    private var bundle: Bundle?

    // MARK: - Initialization
    private init() {
        // Load saved language preference
        if let savedLanguage = UserDefaults.standard.string(forKey: userDefaultsKey),
           let language = AppLanguage(rawValue: savedLanguage) {
            self.currentLanguage = language
        } else {
            self.currentLanguage = .systemDefault
        }

        // Setup locale and bundle
        let localeIdentifier = currentLanguage.localeIdentifier
        self.currentLocale = Locale(identifier: localeIdentifier)
        self.textDirection = Self.determineTextDirection(for: localeIdentifier)

        // Load language bundle
        if currentLanguage != .systemDefault,
           let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            self.bundle = bundle
        } else {
            self.bundle = Bundle.main
        }
    }

    // MARK: - Public Methods

    /// Change the app language
    func setLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }

        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: userDefaultsKey)

        // Update locale
        let localeIdentifier = language.localeIdentifier
        currentLocale = Locale(identifier: localeIdentifier)
        textDirection = Self.determineTextDirection(for: localeIdentifier)

        // Load new bundle
        if language != .systemDefault,
           let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let newBundle = Bundle(path: path) {
            bundle = newBundle
        } else {
            bundle = Bundle.main
        }

        // Post notification for app-wide update
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }

    /// Get localized string
    func localizedString(for key: String, comment: String = "") -> String {
        guard let bundle = bundle else {
            return NSLocalizedString(key, comment: comment)
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Get localized string with format arguments
    func localizedString(for key: String, arguments: CVarArg..., comment: String = "") -> String {
        let format = localizedString(for: key, comment: comment)
        return String(format: format, arguments: arguments)
    }

    /// Check if current language is RTL
    var isRTL: Bool {
        textDirection == .rightToLeft
    }

    /// Get layout direction for SwiftUI
    var layoutDirection: LayoutDirection {
        textDirection.layoutDirection
    }

    // MARK: - Private Helpers

    private static func determineTextDirection(for localeIdentifier: String) -> TextDirection {
        let locale = Locale(identifier: localeIdentifier)
        let languageCode = locale.language.languageCode?.identifier ?? ""

        // RTL languages: Arabic, Hebrew, Persian, Urdu, etc.
        let rtlLanguages = ["ar", "he", "fa", "ur", "yi"]

        return rtlLanguages.contains(languageCode) ? .rightToLeft : .leftToRight
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let languageDidChange = Notification.Name("LanguageDidChange")
}

// MARK: - Environment Key
private struct LocalizationManagerKey: EnvironmentKey {
    static let defaultValue = LocalizationManager.shared
}

extension EnvironmentValues {
    var localizationManager: LocalizationManager {
        get { self[LocalizationManagerKey.self] }
        set { self[LocalizationManagerKey.self] = newValue }
    }
}

// MARK: - View Extension for Language-aware Views
extension View {
    /// Apply localization environment
    func withLocalization() -> some View {
        self
            .environment(\.locale, LocalizationManager.shared.currentLocale)
            .environment(\.layoutDirection, LocalizationManager.shared.layoutDirection)
            .environmentObject(LocalizationManager.shared)
    }
}
