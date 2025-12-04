import SwiftUI

/// 设计系统文本输入框组件
/// Design System Text Field Component
public struct DSTextField: View {

    // MARK: - Field Type

    public enum FieldType {
        case text
        case email
        case password
        case number
        case search
        case url

        var keyboardType: UIKeyboardType {
            switch self {
            case .text, .password: return .default
            case .email: return .emailAddress
            case .number: return .numberPad
            case .search: return .webSearch
            case .url: return .URL
            }
        }

        var textContentType: UITextContentType? {
            switch self {
            case .email: return .emailAddress
            case .password: return .password
            case .url: return .URL
            default: return nil
            }
        }

        var autocapitalization: TextInputAutocapitalization {
            switch self {
            case .email, .password, .url: return .never
            default: return .sentences
            }
        }
    }

    // MARK: - Properties

    @Environment(\.appTheme) private var theme
    @Binding private var text: String
    @FocusState private var isFocused: Bool
    @State private var isPasswordVisible = false

    private let placeholder: String
    private let type: FieldType
    private let icon: String?
    private let error: String?
    private let helper: String?
    private let maxLength: Int?
    private let onCommit: (() -> Void)?

    // MARK: - Initialization

    public init(
        _ placeholder: String,
        text: Binding<String>,
        type: FieldType = .text,
        icon: String? = nil,
        error: String? = nil,
        helper: String? = nil,
        maxLength: Int? = nil,
        onCommit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.type = type
        self.icon = icon
        self.error = error
        self.helper = helper
        self.maxLength = maxLength
        self.onCommit = onCommit
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            // Input Field
            HStack(spacing: DesignTokens.Spacing.sm) {
                // Leading Icon
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: DesignTokens.IconSize.sm))
                        .foregroundColor(iconColor)
                }

                // Text Field
                Group {
                    if type == .password && !isPasswordVisible {
                        SecureField(placeholder, text: $text)
                            .textContentType(type.textContentType)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(type.keyboardType)
                            .textContentType(type.textContentType)
                            .textInputAutocapitalization(type.autocapitalization)
                            .autocorrectionDisabled(type == .email || type == .password || type == .url)
                    }
                }
                .focused($isFocused)
                .onChange(of: text) { newValue in
                    if let maxLength = maxLength {
                        text = String(newValue.prefix(maxLength))
                    }
                }
                .onSubmit {
                    onCommit?()
                }

                // Password Toggle
                if type == .password {
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: DesignTokens.IconSize.sm))
                            .foregroundColor(theme.colors.textSecondary)
                    }
                }

                // Clear Button
                if !text.isEmpty && type != .password {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: DesignTokens.IconSize.sm))
                            .foregroundColor(theme.colors.textSecondary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.Component.inputPadding)
            .background(theme.colors.inputBackground)
            .cornerRadius(DesignTokens.BorderRadius.Component.input)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.BorderRadius.Component.input)
                    .stroke(borderColor, lineWidth: DesignTokens.BorderWidth.medium)
            )

            // Error or Helper Text
            if let error = error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(theme.typography.bodySmall)
                    .foregroundColor(theme.colors.error)
            } else if let helper = helper {
                Text(helper)
                    .font(theme.typography.bodySmall)
                    .foregroundColor(theme.colors.textSecondary)
            }

            // Character Count
            if let maxLength = maxLength {
                HStack {
                    Spacer()
                    Text("\(text.count)/\(maxLength)")
                        .font(theme.typography.bodySmall)
                        .foregroundColor(text.count >= maxLength ? theme.colors.error : theme.colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var iconColor: Color {
        if error != nil {
            return theme.colors.error
        } else if isFocused {
            return theme.colors.primary
        } else {
            return theme.colors.textSecondary
        }
    }

    private var borderColor: Color {
        if error != nil {
            return theme.colors.error
        } else if isFocused {
            return theme.colors.primary
        } else {
            return theme.colors.border
        }
    }
}

// MARK: - Text Area (Multi-line)

/// 多行文本输入框
public struct DSTextArea: View {

    @Environment(\.appTheme) private var theme
    @Binding private var text: String

    private let placeholder: String
    private let error: String?
    private let helper: String?
    private let maxLength: Int?
    private let minHeight: CGFloat

    public init(
        _ placeholder: String,
        text: Binding<String>,
        error: String? = nil,
        helper: String? = nil,
        maxLength: Int? = nil,
        minHeight: CGFloat = 100
    ) {
        self.placeholder = placeholder
        self._text = text
        self.error = error
        self.helper = helper
        self.maxLength = maxLength
        self.minHeight = minHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            // Text Editor
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.textSecondary)
                        .padding(DesignTokens.Spacing.Component.inputPadding)
                }

                TextEditor(text: $text)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight)
                    .padding(DesignTokens.Spacing.Component.inputPadding)
                    .onChange(of: text) { newValue in
                        if let maxLength = maxLength {
                            text = String(newValue.prefix(maxLength))
                        }
                    }
            }
            .background(theme.colors.inputBackground)
            .cornerRadius(DesignTokens.BorderRadius.Component.input)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.BorderRadius.Component.input)
                    .stroke(error != nil ? theme.colors.error : theme.colors.border, lineWidth: DesignTokens.BorderWidth.medium)
            )

            // Error or Helper Text
            if let error = error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(theme.typography.bodySmall)
                    .foregroundColor(theme.colors.error)
            } else if let helper = helper {
                Text(helper)
                    .font(theme.typography.bodySmall)
                    .foregroundColor(theme.colors.textSecondary)
            }

            // Character Count
            if let maxLength = maxLength {
                HStack {
                    Spacer()
                    Text("\(text.count)/\(maxLength)")
                        .font(theme.typography.bodySmall)
                        .foregroundColor(text.count >= maxLength ? theme.colors.error : theme.colors.textSecondary)
                }
            }
        }
    }
}

// MARK: - Search Field

/// 搜索框
public struct DSSearchField: View {

    @Environment(\.appTheme) private var theme
    @Binding private var text: String
    @FocusState private var isFocused: Bool

    private let placeholder: String
    private let onSearch: ((String) -> Void)?

    public init(
        _ placeholder: String = "搜索...",
        text: Binding<String>,
        onSearch: ((String) -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.onSearch = onSearch
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: DesignTokens.IconSize.sm))
                .foregroundColor(theme.colors.textSecondary)

            TextField(placeholder, text: $text)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .onSubmit {
                    onSearch?(text)
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: DesignTokens.IconSize.sm))
                        .foregroundColor(theme.colors.textSecondary)
                }
            }
        }
        .padding(DesignTokens.Spacing.Component.inputPadding)
        .background(theme.colors.inputBackground)
        .cornerRadius(DesignTokens.BorderRadius.full)
    }
}

// MARK: - Previews

#if DEBUG
struct DSTextField_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                // Basic Text Fields
                DSTextField("用户名", text: .constant(""), icon: "person.fill")
                DSTextField("邮箱", text: .constant(""), type: .email, icon: "envelope.fill")
                DSTextField("密码", text: .constant(""), type: .password, icon: "lock.fill")

                // With Error
                DSTextField(
                    "邮箱",
                    text: .constant("invalid"),
                    type: .email,
                    icon: "envelope.fill",
                    error: "邮箱格式不正确"
                )

                // With Helper Text
                DSTextField(
                    "用户名",
                    text: .constant(""),
                    icon: "person.fill",
                    helper: "用户名将显示在您的个人资料中"
                )

                // With Character Limit
                DSTextField(
                    "个人简介",
                    text: .constant("Hello"),
                    maxLength: 100,
                    helper: "简单介绍一下自己"
                )

                // Search Field
                DSSearchField(text: .constant(""))

                // Text Area
                DSTextArea(
                    "写点什么...",
                    text: .constant(""),
                    maxLength: 500
                )
            }
            .padding()
        }
        .withThemeManager()
        .previewDisplayName("Text Fields")
    }
}
#endif
