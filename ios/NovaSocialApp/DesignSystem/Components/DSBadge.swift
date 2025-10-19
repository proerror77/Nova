import SwiftUI

/// 设计系统徽章组件
/// Design System Badge Component
public struct DSBadge: View {

    // MARK: - Badge Style

    public enum Style {
        case primary
        case secondary
        case success
        case warning
        case error
        case info
        case neutral

        func color(theme: AppTheme) -> Color {
            switch self {
            case .primary: return theme.colors.primary
            case .secondary: return theme.colors.secondary
            case .success: return theme.colors.success
            case .warning: return theme.colors.warning
            case .error: return theme.colors.error
            case .info: return theme.colors.info
            case .neutral: return theme.colors.textSecondary
            }
        }
    }

    // MARK: - Badge Size

    public enum Size {
        case small
        case medium
        case large

        var fontSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return DesignTokens.Typography.FontSize.xs
            case .large: return DesignTokens.Typography.FontSize.sm
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return DesignTokens.Spacing.xs
            case .medium: return DesignTokens.Spacing.sm
            case .large: return DesignTokens.Spacing.md
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small: return DesignTokens.Spacing.xs / 2
            case .medium: return DesignTokens.Spacing.xs
            case .large: return DesignTokens.Spacing.sm
            }
        }
    }

    // MARK: - Properties

    @Environment(\.appTheme) private var theme

    private let text: String
    private let style: Style
    private let size: Size
    private let isOutlined: Bool

    // MARK: - Initialization

    public init(
        _ text: String,
        style: Style = .primary,
        size: Size = .medium,
        isOutlined: Bool = false
    ) {
        self.text = text
        self.style = style
        self.size = size
        self.isOutlined = isOutlined
    }

    // MARK: - Body

    public var body: some View {
        Text(text)
            .font(.system(size: size.fontSize, weight: .semibold))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(backgroundColor)
            .cornerRadius(DesignTokens.BorderRadius.Component.badge)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.BorderRadius.Component.badge)
                    .stroke(borderColor, lineWidth: isOutlined ? DesignTokens.BorderWidth.thin : 0)
            )
    }

    // MARK: - Computed Properties

    private var backgroundColor: Color {
        if isOutlined {
            return .clear
        } else {
            return style.color(theme: theme)
        }
    }

    private var foregroundColor: Color {
        if isOutlined {
            return style.color(theme: theme)
        } else {
            return .white
        }
    }

    private var borderColor: Color {
        style.color(theme: theme)
    }
}

// MARK: - Notification Badge (Dot)

/// 通知徽章（圆点）
public struct DSNotificationBadge: View {

    @Environment(\.appTheme) private var theme

    private let count: Int?
    private let maxCount: Int
    private let style: DSBadge.Style

    public init(
        count: Int? = nil,
        maxCount: Int = 99,
        style: DSBadge.Style = .error
    ) {
        self.count = count
        self.maxCount = maxCount
        self.style = style
    }

    public var body: some View {
        Group {
            if let count = count, count > 0 {
                Text(displayText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, count > 9 ? 5 : 0)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(style.color(theme: theme))
                    .clipShape(Circle())
            } else if count == nil {
                Circle()
                    .fill(style.color(theme: theme))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var displayText: String {
        guard let count = count else { return "" }
        return count > maxCount ? "\(maxCount)+" : "\(count)"
    }
}

// MARK: - Status Badge

/// 状态徽章（带图标）
public struct DSStatusBadge: View {

    @Environment(\.appTheme) private var theme

    private let text: String
    private let icon: String?
    private let style: DSBadge.Style
    private let isOutlined: Bool

    public init(
        _ text: String,
        icon: String? = nil,
        style: DSBadge.Style = .primary,
        isOutlined: Bool = false
    ) {
        self.text = text
        self.icon = icon
        self.style = style
        self.isOutlined = isOutlined
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
            }

            Text(text)
                .font(.system(size: DesignTokens.Typography.FontSize.xs, weight: .semibold))
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(backgroundColor)
        .cornerRadius(DesignTokens.BorderRadius.Component.badge)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.BorderRadius.Component.badge)
                .stroke(borderColor, lineWidth: isOutlined ? DesignTokens.BorderWidth.thin : 0)
        )
    }

    private var backgroundColor: Color {
        if isOutlined {
            return .clear
        } else {
            return style.color(theme: theme)
        }
    }

    private var foregroundColor: Color {
        if isOutlined {
            return style.color(theme: theme)
        } else {
            return .white
        }
    }

    private var borderColor: Color {
        style.color(theme: theme)
    }
}

// MARK: - Previews

#if DEBUG
struct DSBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            // Standard Badges
            Group {
                Text("Badge Styles")
                    .font(.headline)

                HStack(spacing: DesignTokens.Spacing.sm) {
                    DSBadge("Primary", style: .primary)
                    DSBadge("Secondary", style: .secondary)
                    DSBadge("Success", style: .success)
                }

                HStack(spacing: DesignTokens.Spacing.sm) {
                    DSBadge("Warning", style: .warning)
                    DSBadge("Error", style: .error)
                    DSBadge("Info", style: .info)
                }
            }

            Divider()

            // Outlined Badges
            Group {
                Text("Outlined Badges")
                    .font(.headline)

                HStack(spacing: DesignTokens.Spacing.sm) {
                    DSBadge("Primary", style: .primary, isOutlined: true)
                    DSBadge("Success", style: .success, isOutlined: true)
                    DSBadge("Error", style: .error, isOutlined: true)
                }
            }

            Divider()

            // Badge Sizes
            Group {
                Text("Badge Sizes")
                    .font(.headline)

                VStack(spacing: DesignTokens.Spacing.sm) {
                    DSBadge("Small", size: .small)
                    DSBadge("Medium", size: .medium)
                    DSBadge("Large", size: .large)
                }
            }

            Divider()

            // Notification Badges
            Group {
                Text("Notification Badges")
                    .font(.headline)

                HStack(spacing: DesignTokens.Spacing.xl) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)

                        DSNotificationBadge(count: 5)
                            .offset(x: 8, y: -8)
                    }

                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)

                        DSNotificationBadge(count: 99)
                            .offset(x: 8, y: -8)
                    }

                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)

                        DSNotificationBadge(count: 100)
                            .offset(x: 8, y: -8)
                    }

                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)

                        DSNotificationBadge()
                            .offset(x: 8, y: -8)
                    }
                }
            }

            Divider()

            // Status Badges
            Group {
                Text("Status Badges")
                    .font(.headline)

                VStack(spacing: DesignTokens.Spacing.sm) {
                    DSStatusBadge("在线", icon: "circle.fill", style: .success)
                    DSStatusBadge("离线", icon: "circle.fill", style: .neutral)
                    DSStatusBadge("忙碌", icon: "circle.fill", style: .warning)
                    DSStatusBadge("已验证", icon: "checkmark.seal.fill", style: .info)
                }
            }
        }
        .padding()
        .withThemeManager()
        .previewDisplayName("Badges")
    }
}
#endif
