import SwiftUI

/// 列表项组件 - 标准化的列表行
/// List Item Component - Standardized list row
public struct DSListItem<Leading: View, Trailing: View>: View {

    // MARK: - Properties

    @Environment(\.appTheme) private var theme

    private let title: String
    private let subtitle: String?
    private let leading: Leading?
    private let trailing: Trailing?
    private let showChevron: Bool
    private let action: (() -> Void)?

    // MARK: - Initialization

    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        showChevron: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
        self.showChevron = showChevron
        self.action = action
    }

    // MARK: - Body

    public var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: DesignTokens.Spacing.md) {
                // Leading content
                if !(leading is EmptyView) {
                    leading
                }

                // Title and Subtitle
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(theme.typography.bodyLarge)
                        .foregroundColor(theme.colors.text)
                        .lineLimit(1)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(theme.typography.bodySmall)
                            .foregroundColor(theme.colors.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Trailing content
                if !(trailing is EmptyView) {
                    trailing
                }

                // Chevron
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(theme.colors.textTertiary)
                }
            }
            .padding(.vertical, DesignTokens.Spacing.sm)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(action == nil)
    }
}

// MARK: - Convenience Initializers

extension DSListItem where Leading == AnyView, Trailing == EmptyView {
    /// 带图标的列表项
    public init(
        icon: String,
        iconColor: Color? = nil,
        title: String,
        subtitle: String? = nil,
        showChevron: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: {
                AnyView(
                    Image(systemName: icon)
                        .font(.system(size: DesignTokens.IconSize.md))
                        .foregroundColor(iconColor)
                )
            },
            trailing: { EmptyView() },
            showChevron: showChevron,
            action: action
        )
    }

    /// 带头像的列表项
    public init(
        avatarURL: String?,
        title: String,
        subtitle: String? = nil,
        showChevron: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: {
                AnyView(
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                        )
                )
            },
            trailing: { EmptyView() },
            showChevron: showChevron,
            action: action
        )
    }
}

extension DSListItem where Leading == EmptyView, Trailing == AnyView {
    /// 带切换开关的列表项
    public init(
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { EmptyView() },
            trailing: {
                AnyView(
                    Toggle("", isOn: isOn)
                        .labelsHidden()
                )
            },
            showChevron: false,
            action: nil
        )
    }

    /// 带徽章的列表项
    public init(
        title: String,
        subtitle: String? = nil,
        badgeText: String,
        badgeColor: Color? = nil,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { EmptyView() },
            trailing: {
                AnyView(
                    Text(badgeText)
                        .badgeStyle(color: badgeColor, size: .small)
                )
            },
            showChevron: false,
            action: action
        )
    }
}

// MARK: - Empty State

/// 空状态组件
public struct DSEmptyState: View {

    @Environment(\.appTheme) private var theme

    public enum Style {
        case noData
        case noResults
        case error
        case custom(icon: String, title: String, message: String?)
    }

    private let style: Style
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        style: Style,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.style = style
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: iconName)
                .font(.system(size: 60))
                .foregroundColor(theme.colors.textSecondary.opacity(0.5))

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(titleText)
                    .font(theme.typography.titleLarge)
                    .foregroundColor(theme.colors.text)

                if let message = messageText {
                    Text(message)
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                }
            }

            if let actionTitle = actionTitle, let action = action {
                DSButton(actionTitle, action: action)
                    .padding(.top, DesignTokens.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.xl)
    }

    private var iconName: String {
        switch style {
        case .noData:
            return "tray"
        case .noResults:
            return "magnifyingglass"
        case .error:
            return "exclamationmark.triangle"
        case .custom(let icon, _, _):
            return icon
        }
    }

    private var titleText: String {
        switch style {
        case .noData:
            return "No Data"
        case .noResults:
            return "No Results Found"
        case .error:
            return "Something Went Wrong"
        case .custom(_, let title, _):
            return title
        }
    }

    private var messageText: String? {
        switch style {
        case .noData:
            return "There's nothing here yet. Check back later!"
        case .noResults:
            return "Try adjusting your search or filters"
        case .error:
            return "We encountered an error. Please try again."
        case .custom(_, _, let message):
            return message
        }
    }
}

// MARK: - List Section Header

/// 列表分区标题
public struct DSSectionHeader: View {

    @Environment(\.appTheme) private var theme

    private let title: String
    private let subtitle: String?
    private let action: (() -> Void)?
    private let actionTitle: String?

    public init(
        _ title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(theme.typography.titleMedium)
                    .foregroundColor(theme.colors.text)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(theme.typography.bodySmall)
                        .foregroundColor(theme.colors.textSecondary)
                }
            }

            Spacer()

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(theme.typography.labelLarge)
                        .foregroundColor(theme.colors.primary)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

// MARK: - Previews

#if DEBUG
struct DSListItem_Previews: PreviewProvider {
    @State private static var toggleState = false

    static var previews: some View {
        ScrollView {
            VStack(spacing: 0) {
                Group {
                    DSSectionHeader("Settings", actionTitle: "Edit") {}

                    DSListItem(
                        icon: "person.fill",
                        iconColor: .blue,
                        title: "Profile",
                        subtitle: "Edit your personal information",
                        showChevron: true
                    ) {}

                    DSInsetDivider()

                    DSListItem(
                        icon: "bell.fill",
                        iconColor: .orange,
                        title: "Notifications",
                        showChevron: true
                    ) {}

                    DSInsetDivider()

                    DSListItem(
                        title: "Dark Mode",
                        subtitle: "Enable dark theme",
                        isOn: .constant(false)
                    )
                }

                DSDivider()
                    .padding(.vertical, DesignTokens.Spacing.md)

                Group {
                    DSSectionHeader("Recent", subtitle: "Last 7 days")

                    DSListItem(
                        avatarURL: nil,
                        title: "John Doe",
                        subtitle: "Sent you a friend request",
                        showChevron: true
                    ) {}

                    DSInsetDivider()

                    DSListItem(
                        title: "New Message",
                        subtitle: "You have 5 unread messages",
                        badgeText: "5",
                        badgeColor: .red
                    ) {}
                }

                DSDivider()
                    .padding(.vertical, DesignTokens.Spacing.md)

                DSEmptyState(
                    style: .noResults,
                    actionTitle: "Clear Filters"
                ) {}
                    .frame(height: 300)
            }
        }
        .withThemeManager()
        .previewDisplayName("Light Mode")

        ScrollView {
            VStack(spacing: 0) {
                DSListItem(
                    icon: "gear",
                    title: "Settings",
                    showChevron: true
                ) {}

                DSEmptyState(style: .noData)
                    .frame(height: 300)
            }
        }
        .environmentObject(ThemeManager.previewDark)
        .appTheme(ThemeManager.previewDark.currentTheme)
        .background(Color.black)
        .previewDisplayName("Dark Mode")
    }
}
#endif
