import SwiftUI
import UIKit

// MARK: - Design Tokens
/// 统一的设计规范，供所有页面使用
struct DesignTokens {
    // MARK: - Colors

    /// Brand Colors
    static let accentColor = Color(red: 0.82, green: 0.11, blue: 0.26)
    static let accentLight = Color(red: 1, green: 0.78, blue: 0.78)

    /// Background Colors
    static let backgroundColor = Color.dynamic(
        light: UIColor(red: 0.97, green: 0.96, blue: 0.96, alpha: 1.0),
        dark: UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)
    )
    static let surface = Color.dynamic(
        light: UIColor.white,
        dark: UIColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0)
    )
    static let cardBackground = surface
    static let overlayBackground = Color.black.opacity(0.4)
    static let loadingBackground = Color.dynamic(
        light: UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0),
        dark: UIColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1.0)
    )

    /// Text Colors
    static let textPrimary = Color.dynamic(
        light: UIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1.0),
        dark: UIColor(red: 0.87, green: 0.87, blue: 0.88, alpha: 1.0)
    )
    static let textSecondary = Color.dynamic(
        light: UIColor(red: 0.53, green: 0.53, blue: 0.54, alpha: 1.0),
        dark: UIColor(red: 0.68, green: 0.68, blue: 0.70, alpha: 1.0)
    )
    static let textTertiary = Color.dynamic(
        light: UIColor(red: 0.32, green: 0.32, blue: 0.32, alpha: 1.0),
        dark: UIColor(red: 0.76, green: 0.76, blue: 0.78, alpha: 1.0)
    )
    static let textMuted = Color.dynamic(
        light: UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1.0),
        dark: UIColor(red: 0.5, green: 0.5, blue: 0.52, alpha: 1.0)
    )
    static let textOnAccent = Color.white

    /// UI Element Colors
    static let borderColor = Color.dynamic(
        light: UIColor(red: 0.74, green: 0.74, blue: 0.74, alpha: 1.0),
        dark: UIColor(red: 0.32, green: 0.32, blue: 0.33, alpha: 1.0)
    )
    static let dividerColor = Color.dynamic(
        light: UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.0),
        dark: UIColor(red: 0.24, green: 0.24, blue: 0.25, alpha: 1.0)
    )
    static let tileBackground = Color.dynamic(
        light: UIColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0),
        dark: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1.0)
    )
    static let tileSeparator = Color.dynamic(
        light: UIColor(red: 0.91, green: 0.91, blue: 0.91, alpha: 1.0),
        dark: UIColor(red: 0.24, green: 0.24, blue: 0.25, alpha: 1.0)
    )
    static let placeholderColor = Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
    static let avatarPlaceholder = Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
    static let indicatorActive = Color(red: 0.82, green: 0.11, blue: 0.26)
    static let indicatorInactive = Color(red: 0.73, green: 0.73, blue: 0.73)

    /// Chat Colors
    static let chatBubbleOther = Color.dynamic(
        light: UIColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0),
        dark: UIColor(red: 0.22, green: 0.22, blue: 0.23, alpha: 1.0)
    )
    static let inputBackground = Color.dynamic(
        light: UIColor(red: 0.53, green: 0.53, blue: 0.53, alpha: 0.2),
        dark: UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1.0)
    )
    static let attachmentBackground = Color.dynamic(
        light: UIColor(red: 0.91, green: 0.91, blue: 0.91, alpha: 1.0),
        dark: UIColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1.0)
    )

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

    // MARK: - Typography Sizes (Legacy - 建议使用 Typography 结构体)

    static let fontCaption: CGFloat = 9
    static let fontSmall: CGFloat = 11
    static let fontBody: CGFloat = 13
    static let fontMedium: CGFloat = 14
    static let fontLarge: CGFloat = 16
    static let fontTitle: CGFloat = 18
    static let fontHeadline: CGFloat = 22
}

// MARK: - Typography System (从 Figma 导出)
/// 统一的字体样式系统，基于 Figma 设计规范
struct Typography {

    // MARK: - Regular (400)

    /// Regular 9pt - 用于最小文字、标签
    static let regular9 = Font.system(size: 9, weight: .regular)

    /// Regular 10pt - 用于辅助信息
    static let regular10 = Font.system(size: 10, weight: .regular)

    /// Regular 12pt - 用于小号正文、说明文字
    static let regular12 = Font.system(size: 12, weight: .regular)

    /// Regular 14pt - 用于正文
    static let regular14 = Font.system(size: 14, weight: .regular)

    /// Regular 16pt - 用于大号正文
    static let regular16 = Font.system(size: 16, weight: .regular)

    // MARK: - Extended Regular (项目扩展)

    /// Regular 13pt - 用于辅助正文
    static let regular13 = Font.system(size: 13, weight: .regular)

    /// Regular 15pt - 用于搜索框等
    static let regular15 = Font.system(size: 15, weight: .regular)

    /// Regular 18pt - 用于设置项
    static let regular18 = Font.system(size: 18, weight: .regular)

    /// Regular 20pt - 用于图标
    static let regular20 = Font.system(size: 20, weight: .regular)

    // MARK: - Semibold (600)

    /// Semibold 14pt - 用于强调文字、按钮
    static let semibold14 = Font.system(size: 14, weight: .semibold)

    /// Semibold 16pt - 用于小标题
    static let semibold16 = Font.system(size: 16, weight: .semibold)

    /// Semibold 24pt - 用于大标题
    static let semibold24 = Font.system(size: 24, weight: .semibold)

    // MARK: - Extended Semibold/Medium (项目扩展)

    /// Semibold 13pt
    static let semibold13 = Font.system(size: 13, weight: .semibold)

    /// Semibold 15pt
    static let semibold15 = Font.system(size: 15, weight: .semibold)

    /// Semibold 17pt
    static let semibold17 = Font.system(size: 17, weight: .semibold)

    /// Semibold 18pt
    static let semibold18 = Font.system(size: 18, weight: .semibold)

    /// Semibold 20pt
    static let semibold20 = Font.system(size: 20, weight: .semibold)

    /// Semibold 22pt
    static let semibold22 = Font.system(size: 22, weight: .semibold)

    // MARK: - Bold (700)

    /// Bold 12pt - 用于强调小文字
    static let bold12 = Font.system(size: 12, weight: .bold)

    // MARK: - Extended Bold (项目扩展)

    /// Bold 16pt
    static let bold16 = Font.system(size: 16, weight: .bold)

    /// Bold 17pt
    static let bold17 = Font.system(size: 17, weight: .bold)

    /// Bold 18pt
    static let bold18 = Font.system(size: 18, weight: .bold)

    /// Bold 19pt
    static let bold19 = Font.system(size: 19, weight: .bold)

    /// Bold 20pt
    static let bold20 = Font.system(size: 20, weight: .bold)

    /// Bold 22pt
    static let bold22 = Font.system(size: 22, weight: .bold)

    /// Bold 24pt
    static let bold24 = Font.system(size: 24, weight: .bold)

    // MARK: - Heavy (900)

    /// Heavy 16pt - 用于特别强调
    static let heavy16 = Font.system(size: 16, weight: .heavy)

    // MARK: - Light (300)

    /// Light 14pt - 用于轻量文字
    static let light14 = Font.system(size: 14, weight: .light)

    // MARK: - Thin (100)

    /// Thin 11pt - 用于极轻文字
    static let thin11 = Font.system(size: 11, weight: .thin)

    // MARK: - 语义化别名 (推荐使用)

    /// 标题 - Semibold 24pt
    static let title = semibold24

    /// 副标题 - Semibold 16pt
    static let subtitle = semibold16

    /// 正文 - Regular 14pt
    static let body = regular14

    /// 正文大号 - Regular 16pt
    static let bodyLarge = regular16

    /// 说明文字 - Regular 12pt
    static let caption = regular12

    /// 小说明 - Regular 10pt
    static let captionSmall = regular10

    /// 按钮文字 - Semibold 14pt
    static let button = semibold14

    /// 标签文字 - Regular 9pt
    static let label = regular9
}

// MARK: - Line Height 行高配置
struct LineHeight {
    static let regular9: CGFloat = 10.8
    static let regular10: CGFloat = 12
    static let regular12: CGFloat = 14.4
    static let regular14: CGFloat = 16.8
    static let regular16: CGFloat = 19.2
    static let semibold14: CGFloat = 16.8
    static let semibold16: CGFloat = 19.2
    static let semibold24: CGFloat = 28.8
    static let bold12: CGFloat = 14.4
    static let heavy16: CGFloat = 19.2
    static let light14: CGFloat = 16.8
    static let thin11: CGFloat = 13.2
}

// MARK: - Letter Spacing 字间距配置
struct LetterSpacing {
    static let regular9: CGFloat = 0.36
    static let regular10: CGFloat = 0
    static let regular12: CGFloat = 0.24
    static let regular14: CGFloat = 0.28
    static let regular16: CGFloat = 0
    static let semibold14: CGFloat = 0.28
    static let semibold16: CGFloat = 0
    static let semibold24: CGFloat = 0
    static let bold12: CGFloat = 0.24
    static let heavy16: CGFloat = 0.32
    static let light14: CGFloat = 0
    static let thin11: CGFloat = 0.22
}

// MARK: - Text Style Modifier (完整样式应用)
extension View {
    /// 应用完整的 Figma 文字样式（包含字体、行高、字间距）
    func textStyle(_ font: Font, lineHeight: CGFloat, letterSpacing: CGFloat = 0) -> some View {
        self
            .font(font)
            .lineSpacing(lineHeight - 16) // 近似行高调整
            .tracking(letterSpacing)
    }

    // MARK: - 快捷样式方法

    /// 标题样式 - Semibold 24pt
    func titleStyle() -> some View {
        textStyle(Typography.title, lineHeight: LineHeight.semibold24)
    }

    /// 副标题样式 - Semibold 16pt
    func subtitleStyle() -> some View {
        textStyle(Typography.subtitle, lineHeight: LineHeight.semibold16)
    }

    /// 正文样式 - Regular 14pt
    func bodyStyle() -> some View {
        textStyle(Typography.body, lineHeight: LineHeight.regular14, letterSpacing: LetterSpacing.regular14)
    }

    /// 说明文字样式 - Regular 12pt
    func captionStyle() -> some View {
        textStyle(Typography.caption, lineHeight: LineHeight.regular12, letterSpacing: LetterSpacing.regular12)
    }

    /// 按钮文字样式 - Semibold 14pt
    func buttonStyle() -> some View {
        textStyle(Typography.button, lineHeight: LineHeight.semibold14, letterSpacing: LetterSpacing.semibold14)
    }
}

private extension Color {
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Theme Manager
/// 全局主題管理（深色 / 淺色）
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published private(set) var isDarkMode: Bool

    private let userDefaultsKey = "ICERED_Theme_IsDarkMode"

    private init() {
        if let stored = UserDefaults.standard.object(forKey: userDefaultsKey) as? Bool {
            self.isDarkMode = stored
        } else {
            self.isDarkMode = false
        }

        applyAppearance()
    }

    /// 套用主題並持久化到 UserDefaults
    func apply(isDarkMode: Bool) {
        guard self.isDarkMode != isDarkMode else { return }
        self.isDarkMode = isDarkMode
        UserDefaults.standard.set(isDarkMode, forKey: userDefaultsKey)
        applyAppearance()
    }

    /// SwiftUI 用來控制全局 ColorScheme
    var colorScheme: ColorScheme? {
        isDarkMode ? .dark : .light
    }

    /// 對整個 App 的 UIWindow 套用深色 / 淺色樣式，
    /// 確保使用 UIColor 動態色的地方也能跟著切換。
    private func applyAppearance() {
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    window.overrideUserInterfaceStyle = self.isDarkMode ? .dark : .light
                }
            }
        }
    }
}
