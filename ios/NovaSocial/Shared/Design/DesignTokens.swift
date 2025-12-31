import SwiftUI
import UIKit

// MARK: - Screen Scale Adapter
/// 基于 iPhone 13 Mini 的等比缩放系统
/// 设计稿基准: iPhone 13 Mini (375 x 812 pt)
/// 性能优化：缓存屏幕尺寸避免重复计算
struct ScreenScale {
    /// iPhone 13 Mini 的屏幕宽度 (基准)
    static let baseWidth: CGFloat = 375
    /// iPhone 13 Mini 的屏幕高度 (基准)
    static let baseHeight: CGFloat = 812

    // MARK: - 缓存的屏幕尺寸 (性能优化)
    // Note: Using UIScreen.main for static initialization is acceptable here as these are
    // cached constants computed once at app launch. For iOS 18+, consider migrating to
    // a view-based approach using GeometryReader if dynamic screen changes become necessary.

    /// 当前设备屏幕宽度 (缓存值，启动时计算一次)
    static let screenWidth: CGFloat = {
        // Use connected scenes first (iOS 13+), fallback to base width
        if let screen = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.screen {
            return screen.bounds.width
        }
        // Fallback to base width if no scene available yet
        return baseWidth
    }()

    /// 当前设备屏幕高度 (缓存值，启动时计算一次)
    static let screenHeight: CGFloat = {
        // Use connected scenes first (iOS 13+), fallback to base height
        if let screen = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.screen {
            return screen.bounds.height
        }
        // Fallback to base height if no scene available yet
        return baseHeight
    }()

    /// 宽度缩放比例 (缓存值)
    static let widthScale: CGFloat = screenWidth / baseWidth

    /// 高度缩放比例 (缓存值)
    static let heightScale: CGFloat = screenHeight / baseHeight

    /// 统一缩放比例 (取宽度比例，保持元素比例一致)
    static let scale: CGFloat = widthScale

    /// 水平方向缩放 (用于宽度、水平间距、水平 padding)
    @inlinable
    static func w(_ value: CGFloat) -> CGFloat {
        value * widthScale
    }

    /// 垂直方向缩放 (用于高度、垂直间距、垂直 padding、offset)
    @inlinable
    static func h(_ value: CGFloat) -> CGFloat {
        value * heightScale
    }

    /// 统一缩放 (用于字体大小、圆角、图标尺寸等需要保持比例的元素)
    @inlinable
    static func s(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    /// 字体缩放 (带最小值限制，避免字体过小)
    @inlinable
    static func font(_ size: CGFloat, minSize: CGFloat = 10) -> CGFloat {
        max(size * scale, minSize)
    }
}

// MARK: - CGFloat Extension for Easy Scaling
extension CGFloat {
    /// 水平缩放
    var w: CGFloat { ScreenScale.w(self) }

    /// 垂直缩放
    var h: CGFloat { ScreenScale.h(self) }

    /// 统一缩放
    var s: CGFloat { ScreenScale.s(self) }

    /// 字体缩放
    var f: CGFloat { ScreenScale.font(self) }
}

// MARK: - Int Extension for Easy Scaling
extension Int {
    /// 水平缩放
    var w: CGFloat { ScreenScale.w(CGFloat(self)) }

    /// 垂直缩放
    var h: CGFloat { ScreenScale.h(CGFloat(self)) }

    /// 统一缩放
    var s: CGFloat { ScreenScale.s(CGFloat(self)) }

    /// 字体缩放
    var f: CGFloat { ScreenScale.font(CGFloat(self)) }
}

// MARK: - Double Extension for Easy Scaling
extension Double {
    /// 水平缩放
    var w: CGFloat { ScreenScale.w(CGFloat(self)) }

    /// 垂直缩放
    var h: CGFloat { ScreenScale.h(CGFloat(self)) }

    /// 统一缩放
    var s: CGFloat { ScreenScale.s(CGFloat(self)) }

    /// 字体缩放
    var f: CGFloat { ScreenScale.font(CGFloat(self)) }
}

// MARK: - Typography
/// 统一字体样式
enum Typography {
    // MARK: - SF Pro Display Font Names
    private static let fontRegular = "SFProDisplay-Regular"
    private static let fontMedium = "SFProDisplay-Medium"
    private static let fontSemibold = "SFProDisplay-Semibold"
    private static let fontBold = "SFProDisplay-Bold"
    private static let fontHeavy = "SFProDisplay-Heavy"
    private static let fontLight = "SFProDisplay-Light"
    private static let fontThin = "SFProDisplay-Thin"
    
    // MARK: - Font Validation (Debug)
    #if DEBUG
    /// 在 App 启动时调用此方法验证字体是否正确加载
    /// 使用方法：在 AppDelegate 或 App.swift 中调用 Typography.validateFonts()
    static func validateFonts() {
        print("🔤 === Font Validation ===")
        let fontNames = [fontRegular, fontMedium, fontSemibold, fontBold, fontHeavy, fontLight, fontThin]
        for name in fontNames {
            if UIFont(name: name, size: 14) != nil {
                print("✅ \(name) - loaded successfully")
            } else {
                print("❌ \(name) - FAILED to load!")
            }
        }
        print("🔤 === Available SF Pro Display fonts ===")
        for family in UIFont.familyNames.sorted() where family.contains("SF") || family.contains("Pro") {
            print("Family: \(family)")
            for fontName in UIFont.fontNames(forFamilyName: family) {
                print("  - \(fontName)")
            }
        }
    }
    #endif
    
    // MARK: - Regular weights
    static let regular10: Font = .custom(fontRegular, size: 10.f)
    static let regular12: Font = .custom(fontRegular, size: 12.f)
    static let regular13: Font = .custom(fontRegular, size: 13.f)
    static let regular14: Font = .custom(fontRegular, size: 14.f)
    static let regular15: Font = .custom(fontRegular, size: 15.f)
    static let regular16: Font = .custom(fontRegular, size: 16.f)
    static let regular20: Font = .custom(fontRegular, size: 20.f)

    // MARK: - Light weights
    static let light14: Font = .custom(fontLight, size: 14.f)
    static let thin11: Font = .custom(fontThin, size: 11.f)

    // MARK: - Semibold weights
    static let semibold14: Font = .custom(fontSemibold, size: 14.f)
    static let semibold15: Font = .custom(fontSemibold, size: 15.f)
    static let semibold16: Font = .custom(fontSemibold, size: 16.f)
    static let semibold18: Font = .custom(fontSemibold, size: 18.f)
    static let semibold24: Font = .custom(fontSemibold, size: 24.f)

    // MARK: - Bold weights
    static let bold12: Font = .custom(fontBold, size: 12.f)
    static let bold20: Font = .custom(fontBold, size: 20.f)

    // MARK: - Heavy weights
    static let heavy16: Font = .custom(fontHeavy, size: 16.f)
    
    // MARK: - Medium weights (新增，Figma 常用)
    static let medium14: Font = .custom(fontMedium, size: 14.f)
    static let medium16: Font = .custom(fontMedium, size: 16.f)
    static let medium18: Font = .custom(fontMedium, size: 18.f)
}

// MARK: - Letter Spacing
/// 统一字间距样式
enum LetterSpacing {
    static let thin11: CGFloat = 0
    static let regular12: CGFloat = 0
    static let regular14: CGFloat = 0
    static let semibold14: CGFloat = 0
    static let bold12: CGFloat = 0
    static let heavy16: CGFloat = 0
}

// MARK: - Design Tokens
/// 统一的设计规范，供所有页面使用
struct DesignTokens {
    // MARK: - Colors

    /// Brand Colors
    static let accentColor = Color(red: 0.82, green: 0.11, blue: 0.26)
    static let accentLight = Color(red: 1, green: 0.78, blue: 0.78)

    /// Background Colors
    static let backgroundColor = Color.dynamic(
        light: UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0),
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

    /// Icon Colors
    static let iconActive = Color(red: 0.82, green: 0.11, blue: 0.26)
    static let iconInactive = Color(red: 0.73, green: 0.73, blue: 0.73)

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
    static let searchBarBackground = Color.dynamic(
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

    // MARK: - Typography Sizes

    static let fontCaption: CGFloat = 9
    static let fontSmall: CGFloat = 11
    static let fontBody: CGFloat = 13
    static let fontMedium: CGFloat = 14
    static let fontLarge: CGFloat = 16
    static let fontTitle: CGFloat = 18
    static let fontHeadline: CGFloat = 22
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

    private let userDefaultsKey = "Icered_Theme_IsDarkMode"

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

// MARK: - Glass Effects
/// Modern glass background effects using Material for depth and translucency

extension View {
    /// Applies glass-like effect using ultra thin material
    /// Use for content cards, panels, and surfaces that need depth
    @ViewBuilder
    func glassSurface() -> some View {
        self.background(.ultraThinMaterial)
    }

    /// Applies glass-like effect using thin material
    /// Use for input areas, toolbars, and overlays on media content
    @ViewBuilder
    func glassInputBackground() -> some View {
        self.background(.thinMaterial)
    }

    /// Applies glass-like effect with custom corner radius
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Applies glass-like effect for floating panels and popovers
    @ViewBuilder
    func glassFloatingPanel(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
    }
}
