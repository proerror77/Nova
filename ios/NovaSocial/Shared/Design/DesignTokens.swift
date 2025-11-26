import SwiftUI

// MARK: - Design Tokens
/// 统一的设计规范，供所有页面使用
struct DesignTokens {
    // MARK: - Colors

    /// Brand Colors
    static let accentColor = Color(red: 0.82, green: 0.11, blue: 0.26)
    static let accentLight = Color(red: 1, green: 0.78, blue: 0.78)

    /// Background Colors
    static let backgroundColor = Color(red: 0.97, green: 0.96, blue: 0.96)
    static let white = Color.white
    static let cardBackground = Color.white
    static let overlayBackground = Color.black.opacity(0.4)
    static let loadingBackground = Color(red: 0.95, green: 0.95, blue: 0.95)

    /// Text Colors
    static let textPrimary = Color(red: 0.25, green: 0.25, blue: 0.25)
    static let textSecondary = Color(red: 0.53, green: 0.53, blue: 0.54)
    static let textTertiary = Color(red: 0.32, green: 0.32, blue: 0.32)
    static let textMuted = Color(red: 0.7, green: 0.7, blue: 0.7)
    static let textOnAccent = Color.white

    /// UI Element Colors
    static let borderColor = Color(red: 0.74, green: 0.74, blue: 0.74)
    static let dividerColor = Color(red: 0.93, green: 0.93, blue: 0.93)
    static let placeholderColor = Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
    static let avatarPlaceholder = Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
    static let indicatorActive = Color(red: 0.82, green: 0.11, blue: 0.26)
    static let indicatorInactive = Color(red: 0.73, green: 0.73, blue: 0.73)

    // MARK: - Spacing

    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing10: CGFloat = 10
    static let spacing12: CGFloat = 12
    static let spacing13: CGFloat = 13
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20

    // MARK: - Sizes

    /// Icons
    static let iconSmall: CGFloat = 10
    static let iconMedium: CGFloat = 14
    static let iconLarge: CGFloat = 24
    static let iconXL: CGFloat = 32

    /// Avatars
    static let avatarSmall: CGFloat = 32
    static let avatarMedium: CGFloat = 40
    static let avatarSize: CGFloat = 38
    static let avatarLarge: CGFloat = 48

    /// Layout
    static let topBarHeight: CGFloat = 56
    static let bottomBarHeight: CGFloat = 60
    static let cardCornerRadius: CGFloat = 12
    static let buttonCornerRadius: CGFloat = 20

    /// Tags
    static let tagWidth: CGFloat = 173.36
    static let tagHeight: CGFloat = 30.80

    // MARK: - Typography Sizes

    static let fontCaption: CGFloat = 9
    static let fontSmall: CGFloat = 11
    static let fontBody: CGFloat = 13
    static let fontMedium: CGFloat = 14
    static let fontLarge: CGFloat = 16
    static let fontTitle: CGFloat = 18
    static let fontHeadline: CGFloat = 22
}
