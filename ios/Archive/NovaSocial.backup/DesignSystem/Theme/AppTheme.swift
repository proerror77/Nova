import SwiftUI

/// 应用主题定义
/// App Theme Definition
public struct AppTheme {

    // MARK: - Theme Mode

    public enum Mode: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"
        case system = "System"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .light: return "浅色模式"
            case .dark: return "暗黑模式"
            case .system: return "跟随系统"
            }
        }

        public var icon: String {
            switch self {
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            case .system: return "gear"
            }
        }
    }

    // MARK: - Properties

    public let mode: Mode
    public let colorScheme: ColorScheme?

    // MARK: - Initialization

    public init(mode: Mode = .system, colorScheme: ColorScheme? = nil) {
        self.mode = mode
        self.colorScheme = colorScheme
    }

    // MARK: - Colors

    public var colors: ThemeColors {
        let isDark = resolvedColorScheme == .dark
        return ThemeColors(isDark: isDark)
    }

    // MARK: - Typography

    public var typography: ThemeTypography {
        ThemeTypography()
    }

    // MARK: - Helpers

    public var resolvedColorScheme: ColorScheme {
        switch mode {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return colorScheme ?? .light
        }
    }

    public var isDarkMode: Bool {
        resolvedColorScheme == .dark
    }
}

// MARK: - Theme Colors

public struct ThemeColors {

    let isDark: Bool

    // MARK: Primary Colors

    public var primary: Color {
        DesignTokens.Colors.Primary.primary500
    }

    public var primaryVariant: Color {
        isDark ? DesignTokens.Colors.Primary.primary300 : DesignTokens.Colors.Primary.primary700
    }

    public var onPrimary: Color {
        DesignTokens.Colors.Neutral.neutral0
    }

    // MARK: Secondary Colors

    public var secondary: Color {
        DesignTokens.Colors.Secondary.secondary500
    }

    public var secondaryVariant: Color {
        isDark ? DesignTokens.Colors.Secondary.secondary300 : DesignTokens.Colors.Secondary.secondary700
    }

    public var onSecondary: Color {
        DesignTokens.Colors.Neutral.neutral0
    }

    // MARK: Background Colors

    public var background: Color {
        isDark ? DesignTokens.Colors.Semantic.backgroundDark : DesignTokens.Colors.Semantic.background
    }

    public var surface: Color {
        isDark ? DesignTokens.Colors.Semantic.surfaceDark : DesignTokens.Colors.Semantic.surface
    }

    public var surfaceVariant: Color {
        isDark ? DesignTokens.Colors.Neutral.neutral800 : DesignTokens.Colors.Neutral.neutral100
    }

    // MARK: Text Colors

    public var text: Color {
        isDark ? DesignTokens.Colors.Semantic.textDark : DesignTokens.Colors.Semantic.text
    }

    public var textSecondary: Color {
        isDark ? DesignTokens.Colors.Semantic.textSecondaryDark : DesignTokens.Colors.Semantic.textSecondary
    }

    public var textTertiary: Color {
        isDark ? DesignTokens.Colors.Neutral.neutral500 : DesignTokens.Colors.Neutral.neutral400
    }

    public var onBackground: Color {
        text
    }

    public var onSurface: Color {
        text
    }

    // MARK: Border Colors

    public var border: Color {
        isDark ? DesignTokens.Colors.Semantic.borderDark : DesignTokens.Colors.Semantic.border
    }

    public var borderVariant: Color {
        isDark ? DesignTokens.Colors.Neutral.neutral700 : DesignTokens.Colors.Neutral.neutral200
    }

    // MARK: Accent Colors

    public var success: Color {
        DesignTokens.Colors.Accent.success
    }

    public var warning: Color {
        DesignTokens.Colors.Accent.warning
    }

    public var error: Color {
        DesignTokens.Colors.Accent.error
    }

    public var info: Color {
        DesignTokens.Colors.Accent.info
    }

    // MARK: State Colors

    public var disabled: Color {
        isDark ? DesignTokens.Colors.Semantic.disabledDark : DesignTokens.Colors.Semantic.disabled
    }

    public var overlay: Color {
        Color.black.opacity(DesignTokens.Opacity.overlay)
    }

    public var scrim: Color {
        Color.black.opacity(DesignTokens.Opacity.scrim)
    }

    // MARK: Component-specific Colors

    public var cardBackground: Color {
        isDark ? DesignTokens.Colors.Neutral.neutral900 : DesignTokens.Colors.Neutral.neutral0
    }

    public var inputBackground: Color {
        isDark ? DesignTokens.Colors.Neutral.neutral800 : DesignTokens.Colors.Neutral.neutral50
    }

    public var buttonPrimary: Color {
        primary
    }

    public var buttonSecondary: Color {
        secondary
    }

    public var buttonGhost: Color {
        .clear
    }

    public var buttonDestructive: Color {
        error
    }

    // MARK: Shadows

    public func shadow(_ style: DesignTokens.Shadow.ShadowStyle) -> DesignTokens.Shadow.ShadowStyle {
        isDark ? adjustShadowForDark(style) : style
    }

    private func adjustShadowForDark(_ style: DesignTokens.Shadow.ShadowStyle) -> DesignTokens.Shadow.ShadowStyle {
        DesignTokens.Shadow.ShadowStyle(
            color: style.color.opacity(style.color.opacity * 1.5),
            radius: style.radius,
            x: style.x,
            y: style.y
        )
    }
}

// MARK: - Theme Typography

public struct ThemeTypography {

    // MARK: Display Styles (超大标题)

    public var displayLarge: Font {
        .system(
            size: DesignTokens.Typography.FontSize.xl6,
            weight: DesignTokens.Typography.FontWeight.bold
        )
    }

    public var displayMedium: Font {
        .system(
            size: DesignTokens.Typography.FontSize.xl5,
            weight: DesignTokens.Typography.FontWeight.bold
        )
    }

    public var displaySmall: Font {
        .system(
            size: DesignTokens.Typography.FontSize.xl4,
            weight: DesignTokens.Typography.FontWeight.bold
        )
    }

    // MARK: Headline Styles (标题)

    public var headlineLarge: Font {
        .system(
            size: DesignTokens.Typography.FontSize.xl3,
            weight: DesignTokens.Typography.FontWeight.semibold
        )
    }

    public var headlineMedium: Font {
        .system(
            size: DesignTokens.Typography.FontSize.xl2,
            weight: DesignTokens.Typography.FontWeight.semibold
        )
    }

    public var headlineSmall: Font {
        .system(
            size: DesignTokens.Typography.FontSize.xl,
            weight: DesignTokens.Typography.FontWeight.semibold
        )
    }

    // MARK: Title Styles (小标题)

    public var titleLarge: Font {
        .system(
            size: DesignTokens.Typography.FontSize.lg,
            weight: DesignTokens.Typography.FontWeight.medium
        )
    }

    public var titleMedium: Font {
        .system(
            size: DesignTokens.Typography.FontSize.base,
            weight: DesignTokens.Typography.FontWeight.medium
        )
    }

    public var titleSmall: Font {
        .system(
            size: DesignTokens.Typography.FontSize.sm,
            weight: DesignTokens.Typography.FontWeight.medium
        )
    }

    // MARK: Body Styles (正文)

    public var bodyLarge: Font {
        .system(
            size: DesignTokens.Typography.FontSize.base,
            weight: DesignTokens.Typography.FontWeight.regular
        )
    }

    public var bodyMedium: Font {
        .system(
            size: DesignTokens.Typography.FontSize.sm,
            weight: DesignTokens.Typography.FontWeight.regular
        )
    }

    public var bodySmall: Font {
        .system(
            size: DesignTokens.Typography.FontSize.xs,
            weight: DesignTokens.Typography.FontWeight.regular
        )
    }

    // MARK: Label Styles (标签)

    public var labelLarge: Font {
        .system(
            size: DesignTokens.Typography.FontSize.sm,
            weight: DesignTokens.Typography.FontWeight.medium
        )
    }

    public var labelMedium: Font {
        .system(
            size: DesignTokens.Typography.FontSize.xs,
            weight: DesignTokens.Typography.FontWeight.medium
        )
    }

    public var labelSmall: Font {
        .system(
            size: 10,
            weight: DesignTokens.Typography.FontWeight.medium
        )
    }

    // MARK: Special Styles

    public var code: Font {
        .system(
            size: DesignTokens.Typography.FontSize.sm,
            design: .monospaced
        )
    }

    public var button: Font {
        .system(
            size: DesignTokens.Typography.FontSize.base,
            weight: DesignTokens.Typography.FontWeight.semibold
        )
    }

    public var caption: Font {
        .system(
            size: DesignTokens.Typography.FontSize.xs,
            weight: DesignTokens.Typography.FontWeight.regular
        )
    }

    public var overline: Font {
        .system(
            size: 10,
            weight: DesignTokens.Typography.FontWeight.medium
        )
        .uppercaseSmallCaps()
    }
}

// MARK: - Environment Key

struct ThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme()
}

extension EnvironmentValues {
    public var appTheme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// 应用主题到视图
    public func appTheme(_ theme: AppTheme) -> some View {
        self
            .environment(\.appTheme, theme)
            .preferredColorScheme(theme.mode == .system ? nil : theme.resolvedColorScheme)
    }
}
