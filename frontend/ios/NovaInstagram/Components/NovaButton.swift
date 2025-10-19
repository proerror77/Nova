import SwiftUI

// MARK: - Button Styles

/// Primary action button - high emphasis
struct NovaPrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var fullWidth: Bool = true
    var icon: String? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                    }
                    Text(title)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 14)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .background(
                isEnabled ? DesignColors.brandPrimary : Color.gray.opacity(0.3)
            )
            .cornerRadius(12)
        }
        .disabled(!isEnabled || isLoading)
    }
}

/// Secondary button - medium emphasis
struct NovaSecondaryButton: View {
    let title: String
    let action: () -> Void
    var isEnabled: Bool = true
    var fullWidth: Bool = true
    var icon: String? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(isEnabled ? DesignColors.brandPrimary : Color.gray)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 14)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEnabled ? DesignColors.brandPrimary : Color.gray.opacity(0.3), lineWidth: 1.5)
            )
        }
        .disabled(!isEnabled)
    }
}

/// Text-only button - low emphasis
struct NovaTextButton: View {
    let title: String
    let action: () -> Void
    var isEnabled: Bool = true
    var color: Color = DesignColors.brandPrimary

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isEnabled ? color : Color.gray)
        }
        .disabled(!isEnabled)
    }
}

/// Icon button - for toolbar actions
struct NovaIconButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 20
    var color: Color = DesignColors.textPrimary
    var isEnabled: Bool = true

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundColor(isEnabled ? color : Color.gray)
                .frame(width: 44, height: 44)
        }
        .disabled(!isEnabled)
    }
}

/// Destructive button - for dangerous actions
struct NovaDestructiveButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var fullWidth: Bool = true

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 14)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .background(Color.red)
            .cornerRadius(12)
        }
        .disabled(isLoading)
    }
}

// MARK: - Preview

#if DEBUG
struct NovaButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            NovaPrimaryButton(
                title: "主要操作",
                action: {},
                icon: "checkmark"
            )

            NovaPrimaryButton(
                title: "加載中...",
                action: {},
                isLoading: true
            )

            NovaSecondaryButton(
                title: "次要操作",
                action: {},
                icon: "heart"
            )

            NovaTextButton(
                title: "文本按鈕",
                action: {}
            )

            NovaDestructiveButton(
                title: "刪除",
                action: {}
            )

            HStack(spacing: 16) {
                NovaIconButton(icon: "heart", action: {})
                NovaIconButton(icon: "paperplane", action: {})
                NovaIconButton(icon: "bookmark", action: {})
            }
        }
        .padding()
    }
}
#endif
