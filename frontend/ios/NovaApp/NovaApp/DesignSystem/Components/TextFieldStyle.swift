import SwiftUI

/// Custom TextField wrapper with consistent styling
struct NovaTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .never
    var isSecure: Bool = false
    var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: Theme.IconSize.sm))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textContentType(textContentType)
                        .font(Theme.Typography.body)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(autocapitalization)
                        .font(Theme.Typography.body)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(
                        errorMessage != nil ? Theme.Colors.error : Theme.Colors.border,
                        lineWidth: 1
                    )
            )
            .cornerRadius(Theme.CornerRadius.md)

            if let error = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: Theme.IconSize.xs))
                    Text(error)
                        .font(Theme.Typography.caption)
                }
                .foregroundColor(Theme.Colors.error)
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        NovaTextField(
            placeholder: "Email",
            text: .constant(""),
            icon: "envelope",
            keyboardType: .emailAddress,
            textContentType: .emailAddress
        )

        NovaTextField(
            placeholder: "Password",
            text: .constant(""),
            icon: "lock",
            isSecure: true
        )

        NovaTextField(
            placeholder: "Username",
            text: .constant("invalid"),
            icon: "person",
            errorMessage: "Username is already taken"
        )
    }
    .padding()
}
