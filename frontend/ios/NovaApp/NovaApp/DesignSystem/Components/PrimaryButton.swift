import SwiftUI

/// Primary CTA button with loading state support
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var fullWidth: Bool = true

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.onPrimary))
                }
                Text(title)
                    .font(Theme.Typography.button)
                    .foregroundColor(Theme.Colors.onPrimary)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, Theme.Spacing.md)
            .padding(.horizontal, Theme.Spacing.lg)
            .background(
                (isDisabled || isLoading) ? Theme.Colors.primary.opacity(0.5) : Theme.Colors.primary
            )
            .cornerRadius(Theme.CornerRadius.md)
        }
        .disabled(isDisabled || isLoading)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "Continue", action: {})
        PrimaryButton(title: "Loading...", action: {}, isLoading: true)
        PrimaryButton(title: "Disabled", action: {}, isDisabled: true)
        PrimaryButton(title: "Compact", action: {}, fullWidth: false)
    }
    .padding()
}
