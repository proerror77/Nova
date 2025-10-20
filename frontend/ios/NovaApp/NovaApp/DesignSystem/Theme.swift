import SwiftUI

/// Nova Design System - Single Source of Truth
/// All colors, typography, spacing, and shadows defined here
enum Theme {
    // MARK: - Colors
    enum Colors {
        // Primary
        static let primary = Color("Primary", bundle: nil) // #FF6B6B or custom
        static let primaryVariant = Color("PrimaryVariant", bundle: nil)
        static let onPrimary = Color.white

        // Surface
        static let surface = Color("Surface", bundle: nil)
        static let background = Color("Background", bundle: nil)
        static let onSurface = Color("OnSurface", bundle: nil)
        static let onBackground = Color("OnBackground", bundle: nil)

        // Secondary
        static let secondary = Color("Secondary", bundle: nil)
        static let secondaryVariant = Color("SecondaryVariant", bundle: nil)
        static let onSecondary = Color.white

        // Semantic
        static let success = Color.green
        static let error = Color.red
        static let warning = Color.orange
        static let info = Color.blue

        // Text
        static let textPrimary = Color("TextPrimary", bundle: nil)
        static let textSecondary = Color("TextSecondary", bundle: nil)
        static let textDisabled = Color("TextDisabled", bundle: nil)

        // Dividers & Borders
        static let divider = Color("Divider", bundle: nil)
        static let border = Color("Border", bundle: nil)

        // Skeleton (for loading states)
        static let skeletonBase = Color.gray.opacity(0.2)
        static let skeletonHighlight = Color.gray.opacity(0.3)
    }

    // MARK: - Typography
    enum Typography {
        // Headings
        static let h1 = Font.system(size: 32, weight: .bold, design: .default)
        static let h2 = Font.system(size: 28, weight: .bold, design: .default)
        static let h3 = Font.system(size: 24, weight: .semibold, design: .default)
        static let h4 = Font.system(size: 20, weight: .semibold, design: .default)
        static let h5 = Font.system(size: 18, weight: .medium, design: .default)
        static let h6 = Font.system(size: 16, weight: .medium, design: .default)

        // Body
        static let body = Font.system(size: 16, weight: .regular, design: .default)
        static let bodyBold = Font.system(size: 16, weight: .semibold, design: .default)
        static let bodySmall = Font.system(size: 14, weight: .regular, design: .default)

        // Caption
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let captionBold = Font.system(size: 12, weight: .semibold, design: .default)

        // Button
        static let button = Font.system(size: 16, weight: .semibold, design: .default)
        static let buttonSmall = Font.system(size: 14, weight: .semibold, design: .default)

        // Label
        static let label = Font.system(size: 14, weight: .medium, design: .default)
    }

    // MARK: - Spacing
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius
    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let round: CGFloat = 999 // For circular elements
    }

    // MARK: - Shadows
    enum Shadows {
        static let small: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (
            Color.black.opacity(0.1), 4, 0, 2
        )
        static let medium: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (
            Color.black.opacity(0.15), 8, 0, 4
        )
        static let large: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (
            Color.black.opacity(0.2), 16, 0, 8
        )
    }

    // MARK: - Animation Durations
    enum Animation {
        static let fast: Double = 0.2
        static let normal: Double = 0.3
        static let slow: Double = 0.5
    }

    // MARK: - Icons Sizes
    enum IconSize {
        static let xs: CGFloat = 16
        static let sm: CGFloat = 20
        static let md: CGFloat = 24
        static let lg: CGFloat = 32
        static let xl: CGFloat = 48
    }

    // MARK: - Avatar Sizes
    enum AvatarSize {
        static let xs: CGFloat = 24
        static let sm: CGFloat = 32
        static let md: CGFloat = 48
        static let lg: CGFloat = 64
        static let xl: CGFloat = 96
    }
}

// MARK: - Shadow Modifier Extension
extension View {
    func themeShadow(_ shadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
