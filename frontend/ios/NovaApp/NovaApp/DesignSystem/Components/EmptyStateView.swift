import SwiftUI

/// Reusable empty state view with optional action
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundColor(Theme.Colors.textSecondary)

            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.h4)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(description)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            if let actionTitle = actionTitle, let action = action {
                PrimaryButton(
                    title: actionTitle,
                    action: action,
                    fullWidth: false
                )
                .padding(.top, Theme.Spacing.md)
            }
        }
        .padding(Theme.Spacing.xxl)
    }
}

#Preview {
    VStack {
        EmptyStateView(
            icon: "photo.on.rectangle.angled",
            title: "No Posts Yet",
            description: "Follow people to see their posts in your feed"
        )

        Divider()

        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results Found",
            description: "Try searching for something else",
            actionTitle: "Clear Search",
            action: {}
        )
    }
}
