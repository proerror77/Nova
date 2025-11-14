import SwiftUI

// MARK: - Design Tokens
/// 统一的设计规范，供所有页面使用
struct DesignTokens {
    // Colors
    static let backgroundColor = Color(red: 0.97, green: 0.96, blue: 0.96)
    static let white = Color.white
    static let textPrimary = Color(red: 0.38, green: 0.37, blue: 0.37)
    static let textSecondary = Color(red: 0.68, green: 0.68, blue: 0.68)
    static let accentColor = Color(red: 0.82, green: 0.13, blue: 0.25)
    static let accentLight = Color(red: 1, green: 0.78, blue: 0.78)
    static let borderColor = Color(red: 0.74, green: 0.74, blue: 0.74)
    static let placeholderColor = Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)

    // Spacing
    static let spacing8: CGFloat = 8
    static let spacing16: CGFloat = 16
    static let spacing13: CGFloat = 13

    // Sizes
    static let tagWidth: CGFloat = 173.36
    static let tagHeight: CGFloat = 30.80
    static let avatarSize: CGFloat = 38
    static let topBarHeight: CGFloat = 56  // 统一的顶部导航栏高度（与 HomeView 一致）
}
