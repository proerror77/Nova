import Foundation
import Combine
import SwiftUI

/// 本地化管理器 - 单例模式管理应用语言
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// 当前语言
    @Published private(set) var currentLanguage: Language {
        didSet {
            saveLanguagePreference()
            updateBundle()
        }
    }

    /// 当前 Bundle（用于加载本地化字符串）
    private(set) var bundle: Bundle = Bundle.main

    private let userDefaultsKey = "app.language.preference"

    private init() {
        // 从 UserDefaults 加载保存的语言偏好
        if let savedLanguageCode = UserDefaults.standard.string(forKey: userDefaultsKey),
           let savedLanguage = Language.from(identifier: savedLanguageCode) {
            currentLanguage = savedLanguage
        } else {
            // 使用系统语言
            currentLanguage = Language.fromSystemLanguage()
        }

        updateBundle()
    }

    /// 切换语言
    func setLanguage(_ language: Language) {
        guard currentLanguage != language else { return }
        currentLanguage = language
    }

    /// 获取本地化字符串
    func localizedString(forKey key: String, comment: String = "") -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// 获取带插值的本地化字符串
    func localizedString(forKey key: String, arguments: CVarArg...) -> String {
        let format = localizedString(forKey: key)
        return String(format: format, arguments: arguments)
    }

    // MARK: - Private Methods

    private func updateBundle() {
        if let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            bundle = languageBundle
        } else {
            bundle = Bundle.main
        }
    }

    private func saveLanguagePreference() {
        UserDefaults.standard.set(currentLanguage.rawValue, forKey: userDefaultsKey)
    }
}

// MARK: - SwiftUI Environment Key

private struct LocalizationManagerKey: EnvironmentKey {
    static let defaultValue = LocalizationManager.shared
}

extension EnvironmentValues {
    var localizationManager: LocalizationManager {
        get { self[LocalizationManagerKey.self] }
        set { self[LocalizationManagerKey.self] = newValue }
    }
}

// MARK: - SwiftUI View Extension

extension View {
    /// 监听语言变化并刷新视图
    func localizable() -> some View {
        self.environmentObject(LocalizationManager.shared)
            .environment(\.locale, LocalizationManager.shared.currentLanguage.locale)
    }
}
