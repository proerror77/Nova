import SwiftUI
import Combine

/// 主题管理器 - 负责主题切换和持久化
/// Theme Manager - Responsible for theme switching and persistence
@MainActor
public final class ThemeManager: ObservableObject {

    // MARK: - Singleton

    public static let shared = ThemeManager()

    // MARK: - Published Properties

    @Published public private(set) var currentTheme: AppTheme
    @Published public var themeMode: AppTheme.Mode {
        didSet {
            updateTheme()
            saveThemePreference()
        }
    }

    // MARK: - Private Properties

    private let userDefaults = UserDefaults.standard
    private let themeModeKey = "app.theme.mode"
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        // 从 UserDefaults 读取用户选择的主题
        let savedMode = userDefaults.string(forKey: themeModeKey)
            .flatMap { AppTheme.Mode(rawValue: $0) } ?? .system

        self.themeMode = savedMode
        self.currentTheme = AppTheme(mode: savedMode)

        setupObservers()
    }

    // MARK: - Public Methods

    /// 设置主题模式
    public func setThemeMode(_ mode: AppTheme.Mode) {
        themeMode = mode
    }

    /// 切换到下一个主题
    public func toggleTheme() {
        let allModes = AppTheme.Mode.allCases
        guard let currentIndex = allModes.firstIndex(of: themeMode) else { return }

        let nextIndex = (currentIndex + 1) % allModes.count
        setThemeMode(allModes[nextIndex])
    }

    /// 重置为系统主题
    public func resetToSystemTheme() {
        setThemeMode(.system)
    }

    /// 获取当前是否为暗黑模式
    public var isDarkMode: Bool {
        currentTheme.isDarkMode
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // 监听系统主题变化
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.updateTheme()
            }
            .store(in: &cancellables)
    }

    private func updateTheme() {
        let colorScheme = UITraitCollection.current.userInterfaceStyle == .dark ? ColorScheme.dark : .light
        currentTheme = AppTheme(mode: themeMode, colorScheme: colorScheme)
    }

    private func saveThemePreference() {
        userDefaults.set(themeMode.rawValue, forKey: themeModeKey)
        userDefaults.synchronize()
    }

    // MARK: - System Integration

    /// 监听系统主题变化
    public func handleTraitCollectionChange(_ traitCollection: UITraitCollection) {
        if themeMode == .system {
            updateTheme()
        }
    }
}

// MARK: - View Extension

extension View {
    /// 应用主题管理器
    public func withThemeManager() -> some View {
        self
            .environmentObject(ThemeManager.shared)
            .appTheme(ThemeManager.shared.currentTheme)
    }
}

// MARK: - Preview Helper

#if DEBUG
extension ThemeManager {
    static var preview: ThemeManager {
        let manager = ThemeManager()
        return manager
    }

    static var previewDark: ThemeManager {
        let manager = ThemeManager()
        manager.setThemeMode(.dark)
        return manager
    }

    static var previewLight: ThemeManager {
        let manager = ThemeManager()
        manager.setThemeMode(.light)
        return manager
    }
}
#endif
