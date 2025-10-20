import SwiftUI

/// 设计 Token 系统 - 所有设计决策的单一真实来源
/// Design Tokens System - Single source of truth for all design decisions
public enum DesignTokens {

    // MARK: - Color Tokens

    /// 颜色系统定义
    public enum Colors {

        // MARK: Primary Colors (品牌主色)
        public enum Primary {
            public static let primary50 = Color(hex: "#E3F2FD")
            public static let primary100 = Color(hex: "#BBDEFB")
            public static let primary200 = Color(hex: "#90CAF9")
            public static let primary300 = Color(hex: "#64B5F6")
            public static let primary400 = Color(hex: "#42A5F5")
            public static let primary500 = Color(hex: "#2196F3") // Main brand color
            public static let primary600 = Color(hex: "#1E88E5")
            public static let primary700 = Color(hex: "#1976D2")
            public static let primary800 = Color(hex: "#1565C0")
            public static let primary900 = Color(hex: "#0D47A1")
        }

        // MARK: Secondary Colors (辅助色)
        public enum Secondary {
            public static let secondary50 = Color(hex: "#F3E5F5")
            public static let secondary100 = Color(hex: "#E1BEE7")
            public static let secondary200 = Color(hex: "#CE93D8")
            public static let secondary300 = Color(hex: "#BA68C8")
            public static let secondary400 = Color(hex: "#AB47BC")
            public static let secondary500 = Color(hex: "#9C27B0") // Main secondary color
            public static let secondary600 = Color(hex: "#8E24AA")
            public static let secondary700 = Color(hex: "#7B1FA2")
            public static let secondary800 = Color(hex: "#6A1B9A")
            public static let secondary900 = Color(hex: "#4A148C")
        }

        // MARK: Accent Colors (强调色)
        public enum Accent {
            public static let success = Color(hex: "#4CAF50")
            public static let warning = Color(hex: "#FF9800")
            public static let error = Color(hex: "#F44336")
            public static let info = Color(hex: "#2196F3")
        }

        // MARK: Neutral Colors (中性色)
        public enum Neutral {
            public static let neutral0 = Color(hex: "#FFFFFF")
            public static let neutral50 = Color(hex: "#F9FAFB")
            public static let neutral100 = Color(hex: "#F3F4F6")
            public static let neutral200 = Color(hex: "#E5E7EB")
            public static let neutral300 = Color(hex: "#D1D5DB")
            public static let neutral400 = Color(hex: "#9CA3AF")
            public static let neutral500 = Color(hex: "#6B7280")
            public static let neutral600 = Color(hex: "#4B5563")
            public static let neutral700 = Color(hex: "#374151")
            public static let neutral800 = Color(hex: "#1F2937")
            public static let neutral900 = Color(hex: "#111827")
            public static let neutral1000 = Color(hex: "#000000")
        }

        // MARK: Semantic Colors (语义化颜色)
        public enum Semantic {
            public static let background = Color(hex: "#FFFFFF")
            public static let backgroundDark = Color(hex: "#121212")
            public static let surface = Color(hex: "#F9FAFB")
            public static let surfaceDark = Color(hex: "#1E1E1E")
            public static let border = Color(hex: "#E5E7EB")
            public static let borderDark = Color(hex: "#2C2C2C")
            public static let text = Color(hex: "#111827")
            public static let textDark = Color(hex: "#F9FAFB")
            public static let textSecondary = Color(hex: "#6B7280")
            public static let textSecondaryDark = Color(hex: "#9CA3AF")
            public static let disabled = Color(hex: "#D1D5DB")
            public static let disabledDark = Color(hex: "#4B5563")
        }
    }

    // MARK: - Typography Tokens

    /// 字体系统定义
    public enum Typography {

        // MARK: Font Families
        public enum FontFamily {
            public static let primary = "SF Pro"
            public static let secondary = "SF Pro Rounded"
            public static let monospace = "SF Mono"
        }

        // MARK: Font Sizes
        public enum FontSize {
            public static let xs: CGFloat = 12
            public static let sm: CGFloat = 14
            public static let base: CGFloat = 16
            public static let lg: CGFloat = 18
            public static let xl: CGFloat = 20
            public static let xl2: CGFloat = 24
            public static let xl3: CGFloat = 30
            public static let xl4: CGFloat = 36
            public static let xl5: CGFloat = 48
            public static let xl6: CGFloat = 60
        }

        // MARK: Font Weights
        public enum FontWeight {
            public static let thin = Font.Weight.thin
            public static let ultraLight = Font.Weight.ultraLight
            public static let light = Font.Weight.light
            public static let regular = Font.Weight.regular
            public static let medium = Font.Weight.medium
            public static let semibold = Font.Weight.semibold
            public static let bold = Font.Weight.bold
            public static let heavy = Font.Weight.heavy
            public static let black = Font.Weight.black
        }

        // MARK: Line Heights
        public enum LineHeight {
            public static let tight: CGFloat = 1.2
            public static let normal: CGFloat = 1.5
            public static let relaxed: CGFloat = 1.75
            public static let loose: CGFloat = 2.0
        }

        // MARK: Letter Spacing
        public enum LetterSpacing {
            public static let tight: CGFloat = -0.5
            public static let normal: CGFloat = 0
            public static let wide: CGFloat = 0.5
            public static let wider: CGFloat = 1.0
        }
    }

    // MARK: - Spacing Tokens

    /// 间距系统定义（8px 基准）
    public enum Spacing {
        public static let xs: CGFloat = 4      // 0.5x
        public static let sm: CGFloat = 8      // 1x (base)
        public static let md: CGFloat = 16     // 2x
        public static let lg: CGFloat = 24     // 3x
        public static let xl: CGFloat = 32     // 4x
        public static let xl2: CGFloat = 40    // 5x
        public static let xl3: CGFloat = 48    // 6x
        public static let xl4: CGFloat = 64    // 8x
        public static let xl5: CGFloat = 80    // 10x
        public static let xl6: CGFloat = 96    // 12x

        // MARK: Component-specific spacing
        public enum Component {
            public static let buttonPaddingVertical: CGFloat = Spacing.md
            public static let buttonPaddingHorizontal: CGFloat = Spacing.lg
            public static let cardPadding: CGFloat = Spacing.md
            public static let inputPadding: CGFloat = Spacing.md
            public static let sectionSpacing: CGFloat = Spacing.xl
        }
    }

    // MARK: - Border Radius Tokens

    /// 圆角系统定义
    public enum BorderRadius {
        public static let none: CGFloat = 0
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xl2: CGFloat = 32
        public static let full: CGFloat = 9999 // Circle

        // MARK: Component-specific radius
        public enum Component {
            public static let button: CGFloat = BorderRadius.md
            public static let card: CGFloat = BorderRadius.lg
            public static let input: CGFloat = BorderRadius.md
            public static let modal: CGFloat = BorderRadius.xl
            public static let badge: CGFloat = BorderRadius.full
        }
    }

    // MARK: - Shadow Tokens

    /// 阴影系统定义
    public enum Shadow {
        public struct ShadowStyle {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat

            public init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
                self.color = color
                self.radius = radius
                self.x = x
                self.y = y
            }
        }

        public static let none = ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)

        public static let sm = ShadowStyle(
            color: Color.black.opacity(0.05),
            radius: 2,
            x: 0,
            y: 1
        )

        public static let md = ShadowStyle(
            color: Color.black.opacity(0.1),
            radius: 4,
            x: 0,
            y: 2
        )

        public static let lg = ShadowStyle(
            color: Color.black.opacity(0.15),
            radius: 8,
            x: 0,
            y: 4
        )

        public static let xl = ShadowStyle(
            color: Color.black.opacity(0.2),
            radius: 16,
            x: 0,
            y: 8
        )

        // MARK: Dark mode shadows
        public static let smDark = ShadowStyle(
            color: Color.black.opacity(0.3),
            radius: 2,
            x: 0,
            y: 1
        )

        public static let mdDark = ShadowStyle(
            color: Color.black.opacity(0.4),
            radius: 4,
            x: 0,
            y: 2
        )

        public static let lgDark = ShadowStyle(
            color: Color.black.opacity(0.5),
            radius: 8,
            x: 0,
            y: 4
        )
    }

    // MARK: - Border Width Tokens

    /// 边框宽度定义
    public enum BorderWidth {
        public static let none: CGFloat = 0
        public static let thin: CGFloat = 1
        public static let medium: CGFloat = 2
        public static let thick: CGFloat = 4
    }

    // MARK: - Opacity Tokens

    /// 透明度定义
    public enum Opacity {
        public static let transparent: Double = 0.0
        public static let disabled: Double = 0.38
        public static let divider: Double = 0.12
        public static let overlay: Double = 0.5
        public static let scrim: Double = 0.32
        public static let opaque: Double = 1.0
    }

    // MARK: - Z-Index Tokens

    /// 层级定义
    public enum ZIndex {
        public static let base: Double = 0
        public static let dropdown: Double = 1000
        public static let sticky: Double = 1100
        public static let overlay: Double = 1200
        public static let modal: Double = 1300
        public static let toast: Double = 1400
        public static let tooltip: Double = 1500
    }

    // MARK: - Animation Tokens

    /// 动画时长定义
    public enum Duration {
        public static let instant: Double = 0.1
        public static let fast: Double = 0.2
        public static let normal: Double = 0.3
        public static let slow: Double = 0.5
        public static let slower: Double = 0.8
    }

    /// 动画缓动曲线定义
    public enum Easing {
        public static let linear = Animation.linear
        public static let easeIn = Animation.easeIn
        public static let easeOut = Animation.easeOut
        public static let easeInOut = Animation.easeInOut
        public static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
        public static let springBouncy = Animation.spring(response: 0.3, dampingFraction: 0.5)
        public static let springSmooth = Animation.spring(response: 0.5, dampingFraction: 1.0)
    }

    // MARK: - Icon Size Tokens

    /// 图标尺寸定义
    public enum IconSize {
        public static let xs: CGFloat = 16
        public static let sm: CGFloat = 20
        public static let md: CGFloat = 24
        public static let lg: CGFloat = 32
        public static let xl: CGFloat = 40
        public static let xl2: CGFloat = 48
    }

    // MARK: - Breakpoint Tokens

    /// 响应式断点定义
    public enum Breakpoint {
        public static let xs: CGFloat = 320   // iPhone SE
        public static let sm: CGFloat = 375   // iPhone 12 mini
        public static let md: CGFloat = 390   // iPhone 12/13
        public static let lg: CGFloat = 428   // iPhone 12/13 Pro Max
        public static let xl: CGFloat = 768   // iPad mini
        public static let xl2: CGFloat = 1024 // iPad
    }

    // MARK: - Gradient Tokens

    /// 颜色渐变定义
    public enum Gradients {
        /// 主品牌渐变
        public static let primary = LinearGradient(
            colors: [Colors.Primary.primary400, Colors.Primary.primary600],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 辅助渐变
        public static let secondary = LinearGradient(
            colors: [Colors.Secondary.secondary400, Colors.Secondary.secondary600],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 成功渐变
        public static let success = LinearGradient(
            colors: [Color(hex: "#66BB6A"), Color(hex: "#43A047")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 警告渐变
        public static let warning = LinearGradient(
            colors: [Color(hex: "#FFA726"), Color(hex: "#FB8C00")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 错误渐变
        public static let error = LinearGradient(
            colors: [Color(hex: "#EF5350"), Color(hex: "#E53935")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 暗黑模式背景渐变
        public static let darkBackground = LinearGradient(
            colors: [Color(hex: "#1A1A1A"), Color(hex: "#0D0D0D")],
            startPoint: .top,
            endPoint: .bottom
        )

        /// 卡片渐变
        public static let card = LinearGradient(
            colors: [Color(hex: "#FFFFFF"), Color(hex: "#F5F5F5")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// 彩虹渐变（特殊场景）
        public static let rainbow = LinearGradient(
            colors: [
                Color(hex: "#FF6B6B"),
                Color(hex: "#FFD93D"),
                Color(hex: "#6BCF7F"),
                Color(hex: "#4ECDC4"),
                Color(hex: "#5F85DB")
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Blur Tokens

    /// 模糊效果定义
    public enum Blur {
        public static let none: CGFloat = 0
        public static let light: CGFloat = 5
        public static let medium: CGFloat = 10
        public static let heavy: CGFloat = 20
        public static let ultraHeavy: CGFloat = 30
    }

    // MARK: - Layout Tokens

    /// 布局常量定义
    public enum Layout {
        /// 最小触摸区域（符合 Apple HIG）
        public static let minTouchTarget: CGFloat = 44

        /// 标准屏幕边距
        public static let screenPadding: CGFloat = Spacing.md

        /// 列表分隔线高度
        public static let dividerHeight: CGFloat = 1

        /// 列表行高度
        public enum RowHeight {
            public static let compact: CGFloat = 44
            public static let standard: CGFloat = 56
            public static let comfortable: CGFloat = 72
        }

        /// 网格间距
        public enum GridSpacing {
            public static let tight: CGFloat = Spacing.xs
            public static let normal: CGFloat = Spacing.sm
            public static let relaxed: CGFloat = Spacing.md
        }

        /// 最大内容宽度（iPad 等大屏）
        public static let maxContentWidth: CGFloat = 768
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
