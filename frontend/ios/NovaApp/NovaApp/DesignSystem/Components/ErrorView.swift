import SwiftUI

/// Error state view with retry action
struct ErrorView: View {
    let error: Error
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(Theme.Colors.error)

            VStack(spacing: Theme.Spacing.xs) {
                Text("Something went wrong")
                    .font(Theme.Typography.h4)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(error.localizedDescription)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            PrimaryButton(
                title: "Try Again",
                action: retryAction,
                fullWidth: false
            )
            .padding(.top, Theme.Spacing.md)
        }
        .padding(Theme.Spacing.xl)
    }
}

/// Inline error banner
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(Theme.Colors.error)

            Text(message)
                .font(Theme.Typography.bodySmall)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(2)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: Theme.IconSize.xs))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.error.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.error, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }
}

/// Toast notification
struct ToastView: View {
    enum ToastType {
        case success, error, warning, info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return Theme.Colors.success
            case .error: return Theme.Colors.error
            case .warning: return Theme.Colors.warning
            case .info: return Theme.Colors.info
            }
        }
    }

    let type: ToastType
    let message: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
            Text(message)
                .font(Theme.Typography.bodySmall)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.md)
        .themeShadow(Theme.Shadows.medium)
    }
}

#Preview {
    VStack(spacing: 32) {
        ErrorView(
            error: NSError(domain: "", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Network connection failed"
            ]),
            retryAction: {}
        )

        ErrorBanner(
            message: "Failed to load posts. Please try again.",
            onDismiss: {}
        )
        .padding(.horizontal)

        ToastView(type: .success, message: "Post published successfully!")
        ToastView(type: .error, message: "Failed to upload image")
        ToastView(type: .warning, message: "Low storage space")
        ToastView(type: .info, message: "Update available")
    }
    .padding()
}
