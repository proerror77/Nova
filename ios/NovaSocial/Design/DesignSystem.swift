import SwiftUI

/// 完全基于 Figma 设计的设计系统
enum DesignSystem {
    // MARK: - Colors
    enum Colors {
        /// 主色 - 粉红红 (#D11C42)
        static let primary = Color(red: 0.82, green: 0.11, blue: 0.26)

        /// 背景色 - 超浅灰 (#F7F6F6)
        static let background = Color(red: 0.969, green: 0.961, blue: 0.965)

        /// 卡片背景 - 纯白
        static let card = Color(red: 1.0, green: 1.0, blue: 1.0)

        /// 深灰文本 (#3F3F3F)
        static let textDark = Color(red: 0.247, green: 0.247, blue: 0.247)

        /// 中灰文本 (#878889)
        static let textMedium = Color(red: 0.529, green: 0.529, blue: 0.537)

        /// 浅灰分隔线
        static let divider = Color(red: 0.9, green: 0.9, blue: 0.9)
    }

    // MARK: - Typography
    enum Typography {
        /// 大标题 - Helvetica Neue Bold 22pt
        static let title1 = Font.system(size: 22, weight: .bold, design: .default)

        /// 小标题 - Helvetica Neue Bold 18pt
        static let title2 = Font.system(size: 18, weight: .bold, design: .default)

        /// 副标题 - Helvetica Neue Medium 16pt
        static let subtitle = Font.system(size: 16, weight: .medium, design: .default)

        /// 正文 - Helvetica Neue Regular 14pt
        static let body = Font.system(size: 14, weight: .regular, design: .default)

        /// 标签 - Helvetica Neue Regular 9pt
        static let label = Font.system(size: 9, weight: .regular, design: .default)

        /// 标签加粗 - Helvetica Neue Medium 9pt
        static let labelBold = Font.system(size: 9, weight: .medium, design: .default)
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - Corner Radius
    enum CornerRadius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 12
        static let large: CGFloat = 15
    }

    // MARK: - Shadow
    enum Shadow {
        static let subtle = Shadow(
            color: Color.black.opacity(0.05),
            radius: 4,
            x: 0,
            y: 2
        )

        static let medium = Shadow(
            color: Color.black.opacity(0.1),
            radius: 8,
            x: 0,
            y: 4
        )
    }

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - View Extensions
extension View {
    func applyCardStyle() -> some View {
        self
            .background(DesignSystem.Colors.card)
            .cornerRadius(DesignSystem.CornerRadius.large)
            .shadow(
                color: DesignSystem.Shadow.subtle.color,
                radius: DesignSystem.Shadow.subtle.radius,
                x: DesignSystem.Shadow.subtle.x,
                y: DesignSystem.Shadow.subtle.y
            )
    }

    func applyPrimaryButtonStyle() -> some View {
        self
            .font(DesignSystem.Typography.subtitle)
            .foregroundColor(.white)
            .frame(height: 44)
            .background(DesignSystem.Colors.primary)
            .cornerRadius(DesignSystem.CornerRadius.small)
    }
}
