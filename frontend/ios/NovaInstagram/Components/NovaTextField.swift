import SwiftUI

// MARK: - Text Field Styles

/// Standard text input field
struct NovaTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var errorMessage: String? = nil
    var onCommit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(isFocused ? DesignColors.brandPrimary : DesignColors.textSecondary)
                        .frame(width: 20)
                }

                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(.system(size: 15))
                        .textInputAutocapitalization(.never)
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text)
                        .font(.system(size: 15))
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(autocapitalization)
                        .focused($isFocused)
                        .onSubmit {
                            onCommit?()
                        }
                }

                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(DesignColors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DesignColors.surfaceLight)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        errorMessage != nil ? Color.red :
                        isFocused ? DesignColors.brandPrimary : DesignColors.borderLight,
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .cornerRadius(10)

            if let error = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 12))
                }
                .foregroundColor(.red)
            }
        }
    }
}

/// Search text field with specialized styling
struct NovaSearchField: View {
    @Binding var text: String
    var placeholder: String = "搜索..."
    var onSearch: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignColors.textSecondary)

            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .focused($isFocused)
                .onSubmit {
                    onSearch?()
                }

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignColors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignColors.surfaceLight)
        .cornerRadius(20)
    }
}

/// Multi-line text editor
struct NovaTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 100
    var maxHeight: CGFloat = 200

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundColor(DesignColors.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }

            TextEditor(text: $text)
                .font(.system(size: 15))
                .focused($isFocused)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .background(DesignColors.surfaceLight)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isFocused ? DesignColors.brandPrimary : DesignColors.borderLight,
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .cornerRadius(10)
    }
}

// MARK: - Preview

#if DEBUG
struct NovaTextField_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            NovaTextField(
                placeholder: "用戶名",
                text: .constant(""),
                icon: "person"
            )

            NovaTextField(
                placeholder: "郵箱",
                text: .constant("user@example.com"),
                icon: "envelope",
                keyboardType: .emailAddress,
                autocapitalization: .never
            )

            NovaTextField(
                placeholder: "密碼",
                text: .constant(""),
                icon: "lock",
                isSecure: true
            )

            NovaTextField(
                placeholder: "錯誤示例",
                text: .constant("invalid"),
                icon: "exclamationmark.triangle",
                errorMessage: "此字段為必填項"
            )

            NovaSearchField(
                text: .constant("搜索內容")
            )

            NovaTextEditor(
                placeholder: "分享您的想法...",
                text: .constant("")
            )
        }
        .padding()
        .background(DesignColors.surfaceLight)
    }
}
#endif
