import SwiftUI

/// 设计系统警告框组件
/// Design System Alert Component
public struct DSAlert: View {

    // MARK: - Alert Style

    public enum Style {
        case success
        case error
        case warning
        case info

        var color: (AppTheme) -> Color {
            switch self {
            case .success: return { $0.colors.success }
            case .error: return { $0.colors.error }
            case .warning: return { $0.colors.warning }
            case .info: return { $0.colors.info }
            }
        }

        var backgroundColor: (AppTheme) -> Color {
            switch self {
            case .success: return { $0.colors.success.opacity(0.1) }
            case .error: return { $0.colors.error.opacity(0.1) }
            case .warning: return { $0.colors.warning.opacity(0.1) }
            case .info: return { $0.colors.info.opacity(0.1) }
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    // MARK: - Properties

    @Environment(\.appTheme) private var theme

    private let title: String?
    private let message: String
    private let style: Style
    private let isDismissible: Bool
    private let onDismiss: (() -> Void)?

    // MARK: - Initialization

    public init(
        title: String? = nil,
        message: String,
        style: Style = .info,
        isDismissible: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.style = style
        self.isDismissible = isDismissible
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    public var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            // Icon
            Image(systemName: style.icon)
                .font(.system(size: DesignTokens.IconSize.md))
                .foregroundColor(style.color(theme))

            // Content
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                if let title = title {
                    Text(title)
                        .font(theme.typography.titleMedium)
                        .foregroundColor(theme.colors.text)
                }

                Text(message)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Dismiss Button
            if isDismissible {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: DesignTokens.IconSize.sm))
                        .foregroundColor(theme.colors.textSecondary)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(style.backgroundColor(theme))
        .cornerRadius(DesignTokens.BorderRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.BorderRadius.md)
                .stroke(style.color(theme), lineWidth: DesignTokens.BorderWidth.thin)
        )
    }
}

// MARK: - Alert with Actions

/// 带操作按钮的警告框
public struct DSAlertWithActions: View {

    @Environment(\.appTheme) private var theme

    private let title: String
    private let message: String
    private let style: DSAlert.Style
    private let primaryAction: (title: String, action: () -> Void)?
    private let secondaryAction: (title: String, action: () -> Void)?

    public init(
        title: String,
        message: String,
        style: DSAlert.Style = .info,
        primaryAction: (title: String, action: () -> Void)? = nil,
        secondaryAction: (title: String, action: () -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.style = style
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // Header
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: style.icon)
                    .font(.system(size: DesignTokens.IconSize.lg))
                    .foregroundColor(style.color(theme))

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text(title)
                        .font(theme.typography.titleLarge)
                        .foregroundColor(theme.colors.text)

                    Text(message)
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.textSecondary)
                }
            }

            // Actions
            if primaryAction != nil || secondaryAction != nil {
                HStack(spacing: DesignTokens.Spacing.md) {
                    if let secondary = secondaryAction {
                        DSButton(
                            secondary.title,
                            style: .ghost,
                            fullWidth: true
                        ) {
                            secondary.action()
                        }
                    }

                    if let primary = primaryAction {
                        DSButton(
                            primary.title,
                            style: style == .error ? .destructive : .primary,
                            fullWidth: true
                        ) {
                            primary.action()
                        }
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(theme.colors.cardBackground)
        .cornerRadius(DesignTokens.BorderRadius.lg)
        .shadow(
            color: theme.colors.shadow(DesignTokens.Shadow.lg).color,
            radius: theme.colors.shadow(DesignTokens.Shadow.lg).radius,
            x: 0,
            y: 4
        )
    }
}

// MARK: - Inline Alert

/// 内联警告框（简洁版）
public struct DSInlineAlert: View {

    @Environment(\.appTheme) private var theme

    private let message: String
    private let style: DSAlert.Style

    public init(message: String, style: DSAlert.Style = .info) {
        self.message = message
        self.style = style
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: style.icon)
                .font(.system(size: DesignTokens.IconSize.sm))
                .foregroundColor(style.color(theme))

            Text(message)
                .font(theme.typography.bodySmall)
                .foregroundColor(theme.colors.text)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(style.backgroundColor(theme))
        .cornerRadius(DesignTokens.BorderRadius.sm)
    }
}

// MARK: - Previews

#if DEBUG
struct DSAlert_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                // Standard Alerts
                Group {
                    Text("Standard Alerts")
                        .font(.headline)

                    DSAlert(
                        title: "成功",
                        message: "您的操作已成功完成",
                        style: .success
                    )

                    DSAlert(
                        title: "错误",
                        message: "发生了一个错误，请稍后重试",
                        style: .error,
                        isDismissible: true
                    ) {
                        print("Dismissed")
                    }

                    DSAlert(
                        title: "警告",
                        message: "请注意，此操作可能需要一些时间",
                        style: .warning
                    )

                    DSAlert(
                        message: "这是一条普通的信息通知，没有标题",
                        style: .info,
                        isDismissible: true
                    ) {
                        print("Dismissed")
                    }
                }

                Divider()

                // Alerts with Actions
                Group {
                    Text("Alerts with Actions")
                        .font(.headline)

                    DSAlertWithActions(
                        title: "确认删除",
                        message: "您确定要删除这个项目吗？此操作无法撤销。",
                        style: .error,
                        primaryAction: (title: "删除", action: { print("Delete") }),
                        secondaryAction: (title: "取消", action: { print("Cancel") })
                    )

                    DSAlertWithActions(
                        title: "更新可用",
                        message: "发现新版本，是否立即更新？",
                        style: .info,
                        primaryAction: (title: "更新", action: { print("Update") }),
                        secondaryAction: (title: "稍后", action: { print("Later") })
                    )
                }

                Divider()

                // Inline Alerts
                Group {
                    Text("Inline Alerts")
                        .font(.headline)

                    DSInlineAlert(message: "保存成功", style: .success)
                    DSInlineAlert(message: "请检查您的输入", style: .warning)
                    DSInlineAlert(message: "网络连接失败", style: .error)
                    DSInlineAlert(message: "正在处理中...", style: .info)
                }
            }
            .padding()
        }
        .withThemeManager()
        .previewDisplayName("Alerts")
    }
}
#endif
