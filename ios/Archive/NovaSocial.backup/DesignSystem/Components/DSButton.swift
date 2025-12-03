import SwiftUI

/// 设计系统按钮组件
/// Design System Button Component
public struct DSButton: View {

    // MARK: - Button Style

    public enum Style {
        case primary
        case secondary
        case ghost
        case destructive
        case outline

        var defaultBackgroundColor: (AppTheme) -> Color {
            switch self {
            case .primary: return { $0.colors.buttonPrimary }
            case .secondary: return { $0.colors.buttonSecondary }
            case .ghost: return { _ in .clear }
            case .destructive: return { $0.colors.buttonDestructive }
            case .outline: return { _ in .clear }
            }
        }

        var defaultForegroundColor: (AppTheme) -> Color {
            switch self {
            case .primary, .secondary, .destructive:
                return { _ in .white }
            case .ghost:
                return { $0.colors.primary }
            case .outline:
                return { $0.colors.primary }
            }
        }

        var hasBorder: Bool {
            self == .outline || self == .ghost
        }
    }

    // MARK: - Button Size

    public enum Size {
        case small
        case medium
        case large

        var height: CGFloat {
            switch self {
            case .small: return 36
            case .medium: return 44
            case .large: return 52
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return DesignTokens.Typography.FontSize.sm
            case .medium: return DesignTokens.Typography.FontSize.base
            case .large: return DesignTokens.Typography.FontSize.lg
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return DesignTokens.Spacing.md
            case .medium: return DesignTokens.Spacing.lg
            case .large: return DesignTokens.Spacing.xl
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return DesignTokens.IconSize.sm
            case .medium: return DesignTokens.IconSize.md
            case .large: return DesignTokens.IconSize.lg
            }
        }
    }

    // MARK: - Properties

    @Environment(\.appTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    private let title: String
    private let icon: String?
    private let iconPosition: IconPosition
    private let style: Style
    private let size: Size
    private let fullWidth: Bool
    private let isLoading: Bool
    private let action: () -> Void

    public enum IconPosition {
        case leading
        case trailing
    }

    // MARK: - Initialization

    public init(
        _ title: String,
        icon: String? = nil,
        iconPosition: IconPosition = .leading,
        style: Style = .primary,
        size: Size = .medium,
        fullWidth: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.iconPosition = iconPosition
        self.style = style
        self.size = size
        self.fullWidth = fullWidth
        self.isLoading = isLoading
        self.action = action
    }

    // MARK: - Body

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                        .scaleEffect(0.8)
                } else {
                    if let icon = icon, iconPosition == .leading {
                        Image(systemName: icon)
                            .font(.system(size: size.iconSize))
                    }

                    Text(title)
                        .font(.system(size: size.fontSize, weight: .semibold))

                    if let icon = icon, iconPosition == .trailing {
                        Image(systemName: icon)
                            .font(.system(size: size.iconSize))
                    }
                }
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .foregroundColor(foregroundColor)
            .background(backgroundColor)
            .cornerRadius(DesignTokens.BorderRadius.Component.button)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.BorderRadius.Component.button)
                    .stroke(borderColor, lineWidth: style.hasBorder ? DesignTokens.BorderWidth.medium : 0)
            )
        }
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1.0 : DesignTokens.Opacity.disabled)
        .buttonPress()
    }

    // MARK: - Computed Properties

    private var backgroundColor: Color {
        style.defaultBackgroundColor(theme)
    }

    private var foregroundColor: Color {
        style.defaultForegroundColor(theme)
    }

    private var borderColor: Color {
        switch style {
        case .outline:
            return theme.colors.primary
        case .ghost:
            return .clear
        default:
            return .clear
        }
    }
}

// MARK: - Icon Button

/// 图标按钮（仅图标，无文字）
public struct DSIconButton: View {

    @Environment(\.appTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    private let icon: String
    private let style: DSButton.Style
    private let size: DSButton.Size
    private let action: () -> Void

    public init(
        icon: String,
        style: DSButton.Style = .primary,
        size: DSButton.Size = .medium,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.style = style
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size.iconSize))
                .foregroundColor(style.defaultForegroundColor(theme))
                .frame(width: size.height, height: size.height)
                .background(style.defaultBackgroundColor(theme))
                .cornerRadius(DesignTokens.BorderRadius.Component.button)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : DesignTokens.Opacity.disabled)
        .buttonPress()
    }
}

// MARK: - Floating Action Button

/// 浮动操作按钮
public struct DSFloatingActionButton: View {

    @Environment(\.appTheme) private var theme

    private let icon: String
    private let action: () -> Void

    public init(icon: String, action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: DesignTokens.IconSize.lg))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(theme.colors.primary)
                .clipShape(Circle())
                .shadow(
                    color: theme.colors.primary.opacity(0.4),
                    radius: 8,
                    x: 0,
                    y: 4
                )
        }
        .buttonPress()
    }
}

// MARK: - Previews

#if DEBUG
struct DSButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            // Primary Buttons
            Group {
                DSButton("Primary Button", style: .primary) {}
                DSButton("With Icon", icon: "heart.fill", style: .primary) {}
                DSButton("Trailing Icon", icon: "arrow.right", iconPosition: .trailing, style: .primary) {}
                DSButton("Loading", style: .primary, isLoading: true) {}
                DSButton("Full Width", style: .primary, fullWidth: true) {}
            }

            Divider()

            // Secondary Buttons
            Group {
                DSButton("Secondary", style: .secondary) {}
                DSButton("Ghost", style: .ghost) {}
                DSButton("Outline", style: .outline) {}
                DSButton("Destructive", style: .destructive) {}
            }

            Divider()

            // Sizes
            Group {
                DSButton("Small", style: .primary, size: .small) {}
                DSButton("Medium", style: .primary, size: .medium) {}
                DSButton("Large", style: .primary, size: .large) {}
            }

            Divider()

            // Icon Buttons
            HStack(spacing: DesignTokens.Spacing.md) {
                DSIconButton(icon: "heart.fill", style: .primary) {}
                DSIconButton(icon: "message.fill", style: .secondary) {}
                DSIconButton(icon: "share", style: .ghost) {}
                DSIconButton(icon: "trash", style: .destructive) {}
            }

            Divider()

            // Floating Action Button
            DSFloatingActionButton(icon: "plus") {}
        }
        .padding()
        .withThemeManager()
        .previewDisplayName("Light Mode")

        VStack(spacing: DesignTokens.Spacing.lg) {
            DSButton("Primary Button", style: .primary) {}
            DSButton("Secondary", style: .secondary) {}
            DSButton("Ghost", style: .ghost) {}
            DSFloatingActionButton(icon: "plus") {}
        }
        .padding()
        .environmentObject(ThemeManager.previewDark)
        .appTheme(ThemeManager.previewDark.currentTheme)
        .background(Color.black)
        .previewDisplayName("Dark Mode")
    }
}
#endif
