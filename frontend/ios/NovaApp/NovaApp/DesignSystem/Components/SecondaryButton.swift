import SwiftUI

/// Secondary/Outline button with loading state support
struct SecondaryButton: View {
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
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.primary))
                }
                Text(title)
                    .font(Theme.Typography.button)
                    .foregroundColor(
                        (isDisabled || isLoading)
                            ? Theme.Colors.textDisabled
                            : Theme.Colors.primary
                    )
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, Theme.Spacing.md)
            .padding(.horizontal, Theme.Spacing.lg)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(
                        (isDisabled || isLoading)
                            ? Theme.Colors.border.opacity(0.5)
                            : Theme.Colors.primary,
                        lineWidth: 2
                    )
            )
            .cornerRadius(Theme.CornerRadius.md)
        }
        .disabled(isDisabled || isLoading)
    }
}

#Preview {
    VStack(spacing: 16) {
        SecondaryButton(title: "Cancel", action: {})
        SecondaryButton(title: "Loading...", action: {}, isLoading: true)
        SecondaryButton(title: "Disabled", action: {}, isDisabled: true)
        SecondaryButton(title: "Compact", action: {}, fullWidth: false)
    }
    .padding()
}
