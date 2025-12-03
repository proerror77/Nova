import SwiftUI

/// 设计系统卡片组件
/// Design System Card Component
public struct DSCard<Content: View>: View {

    // MARK: - Card Style

    public enum Style {
        case standard
        case elevated
        case outlined
        case filled

        func backgroundColor(theme: AppTheme) -> Color {
            switch self {
            case .standard, .elevated, .outlined:
                return theme.colors.cardBackground
            case .filled:
                return theme.colors.surfaceVariant
            }
        }

        func shadowStyle(theme: AppTheme) -> DesignTokens.Shadow.ShadowStyle {
            switch self {
            case .standard:
                return theme.colors.shadow(DesignTokens.Shadow.sm)
            case .elevated:
                return theme.colors.shadow(DesignTokens.Shadow.lg)
            case .outlined, .filled:
                return DesignTokens.Shadow.none
            }
        }

        var hasBorder: Bool {
            self == .outlined
        }
    }

    // MARK: - Properties

    @Environment(\.appTheme) private var theme

    private let style: Style
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let content: Content

    // MARK: - Initialization

    public init(
        style: Style = .standard,
        padding: CGFloat = DesignTokens.Spacing.Component.cardPadding,
        cornerRadius: CGFloat = DesignTokens.BorderRadius.Component.card,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    // MARK: - Body

    public var body: some View {
        content
            .padding(padding)
            .background(style.backgroundColor(theme: theme))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        theme.colors.border,
                        lineWidth: style.hasBorder ? DesignTokens.BorderWidth.thin : 0
                    )
            )
            .shadow(
                color: style.shadowStyle(theme: theme).color,
                radius: style.shadowStyle(theme: theme).radius,
                x: style.shadowStyle(theme: theme).x,
                y: style.shadowStyle(theme: theme).y
            )
    }
}

// MARK: - Interactive Card

/// 可交互卡片（支持点击）
public struct DSInteractiveCard<Content: View>: View {

    @Environment(\.appTheme) private var theme
    @State private var isPressed = false

    private let style: DSCard.Style
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let action: () -> Void
    private let content: Content

    public init(
        style: DSCard.Style = .standard,
        padding: CGFloat = DesignTokens.Spacing.Component.cardPadding,
        cornerRadius: CGFloat = DesignTokens.BorderRadius.Component.card,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.action = action
        self.content = content()
    }

    public var body: some View {
        Button(action: action) {
            DSCard(style: style, padding: padding, cornerRadius: cornerRadius) {
                content
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(Animations.fast, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Content Card

/// 内容卡片（带标题、副标题和可选操作）
public struct DSContentCard<Content: View>: View {

    @Environment(\.appTheme) private var theme

    private let title: String
    private let subtitle: String?
    private let icon: String?
    private let style: DSCard.Style
    private let action: (() -> Void)?
    private let content: Content

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        style: DSCard.Style = .standard,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.style = style
        self.action = action
        self.content = content()
    }

    public var body: some View {
        DSCard(style: style) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                // Header
                HStack {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: DesignTokens.IconSize.md))
                            .foregroundColor(theme.colors.primary)
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Text(title)
                            .font(theme.typography.titleLarge)
                            .foregroundColor(theme.colors.text)

                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(theme.typography.bodySmall)
                                .foregroundColor(theme.colors.textSecondary)
                        }
                    }

                    Spacer()

                    if action != nil {
                        Button(action: action!) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: DesignTokens.IconSize.sm))
                                .foregroundColor(theme.colors.textSecondary)
                        }
                    }
                }

                // Content
                content
            }
        }
    }
}

// MARK: - Image Card

/// 图片卡片
public struct DSImageCard: View {

    @Environment(\.appTheme) private var theme

    private let image: String
    private let title: String
    private let subtitle: String?
    private let style: DSCard.Style
    private let action: (() -> Void)?

    public init(
        image: String,
        title: String,
        subtitle: String? = nil,
        style: DSCard.Style = .standard,
        action: (() -> Void)? = nil
    ) {
        self.image = image
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.action = action
    }

    public var body: some View {
        let cardContent = VStack(spacing: 0) {
            // Image
            Image(systemName: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 180)
                .clipped()

            // Content
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(theme.typography.titleMedium)
                    .foregroundColor(theme.colors.text)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(theme.typography.bodySmall)
                        .foregroundColor(theme.colors.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let action = action {
            DSInteractiveCard(style: style, padding: 0) {
                cardContent
            } action: {
                action()
            }
        } else {
            DSCard(style: style, padding: 0) {
                cardContent
            }
        }
    }
}

// MARK: - Stats Card

/// 统计卡片
public struct DSStatsCard: View {

    @Environment(\.appTheme) private var theme

    private let title: String
    private let value: String
    private let trend: Trend?
    private let icon: String?
    private let style: DSCard.Style

    public enum Trend {
        case up(String)
        case down(String)
        case neutral(String)

        var color: (AppTheme) -> Color {
            switch self {
            case .up: return { $0.colors.success }
            case .down: return { $0.colors.error }
            case .neutral: return { $0.colors.textSecondary }
            }
        }

        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return "minus"
            }
        }

        var value: String {
            switch self {
            case .up(let val), .down(let val), .neutral(let val):
                return val
            }
        }
    }

    public init(
        title: String,
        value: String,
        trend: Trend? = nil,
        icon: String? = nil,
        style: DSCard.Style = .filled
    ) {
        self.title = title
        self.value = value
        self.trend = trend
        self.icon = icon
        self.style = style
    }

    public var body: some View {
        DSCard(style: style) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack {
                    Text(title)
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.textSecondary)

                    Spacer()

                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: DesignTokens.IconSize.md))
                            .foregroundColor(theme.colors.primary)
                    }
                }

                Text(value)
                    .font(theme.typography.displaySmall)
                    .foregroundColor(theme.colors.text)

                if let trend = trend {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: trend.icon)
                            .font(.system(size: 12))

                        Text(trend.value)
                            .font(theme.typography.bodySmall)
                    }
                    .foregroundColor(trend.color(theme))
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
struct DSCard_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                // Standard Cards
                DSCard {
                    Text("Standard Card")
                }

                DSCard(style: .elevated) {
                    Text("Elevated Card")
                }

                DSCard(style: .outlined) {
                    Text("Outlined Card")
                }

                DSCard(style: .filled) {
                    Text("Filled Card")
                }

                // Interactive Card
                DSInteractiveCard {
                    Text("Tap me!")
                } action: {
                    print("Card tapped")
                }

                // Content Card
                DSContentCard(
                    title: "通知",
                    subtitle: "您有 3 条新消息",
                    icon: "bell.fill",
                    action: {}
                ) {
                    Text("Card content here")
                }

                // Image Card
                DSImageCard(
                    image: "photo",
                    title: "Beautiful Sunset",
                    subtitle: "A stunning view of the sunset over the ocean",
                    action: {}
                )

                // Stats Cards
                HStack(spacing: DesignTokens.Spacing.md) {
                    DSStatsCard(
                        title: "总用户",
                        value: "12.5K",
                        trend: .up("+12%"),
                        icon: "person.3.fill"
                    )

                    DSStatsCard(
                        title: "活跃用户",
                        value: "8.2K",
                        trend: .down("-5%"),
                        icon: "chart.line.uptrend.xyaxis"
                    )
                }
            }
            .padding()
        }
        .withThemeManager()
        .previewDisplayName("Cards")
    }
}
#endif
