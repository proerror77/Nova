//
//  LoginView+Accessibility.swift
//  NovaSocial
//
//  Created by Nova Team
//  Accessibility support for authentication views
//

import SwiftUI

// MARK: - Accessible Text Field

struct AccessibleTextField: View {

    let label: String
    let placeholder: String
    @Binding var text: String

    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .never
    var autocorrectionDisabled: Bool = false
    var errorMessage: String?
    var accessibilityHint: String?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .accessibilityHidden(true) // Combined with text field

            // Text field
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(autocorrectionDisabled)
                .focused($isFocused)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            errorMessage != nil ? Color.red : (isFocused ? Color.blue : Color.clear),
                            lineWidth: 2
                        )
                )
                // Accessibility
                .accessibilityLabel("\(label) text field")
                .accessibilityValue(text.isEmpty ? "Empty" : text)
                .accessibilityHint(accessibilityHint ?? "")
                .accessibilityIdentifier("textfield.\(label.lowercased().replacingOccurrences(of: " ", with: "."))")
                .frame(minHeight: AccessibilityConstants.minTouchTargetSize)

            // Error message
            if let errorMessage = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .accessibilityHidden(true)

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error: \(errorMessage)")
                .accessibilityAddTraits(.isStaticText)
                .onAppear {
                    // Announce error immediately
                    AccessibilityHelper.announce("Error: \(errorMessage)")
                }
            }
        }
    }
}

// MARK: - Accessible Secure Field

struct AccessibleSecureField: View {

    let label: String
    let placeholder: String
    @Binding var text: String

    var textContentType: UITextContentType?
    var errorMessage: String?
    var accessibilityHint: String?

    @State private var isPasswordVisible = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .accessibilityHidden(true)

            // Secure field with toggle
            HStack {
                if isPasswordVisible {
                    TextField(placeholder, text: $text)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($isFocused)
                } else {
                    SecureField(placeholder, text: $text)
                        .textContentType(textContentType)
                        .focused($isFocused)
                }

                Button(action: {
                    isPasswordVisible.toggle()
                    announceVisibilityToggle()
                }) {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                        .frame(
                            width: AccessibilityConstants.minTouchTargetSize,
                            height: AccessibilityConstants.minTouchTargetSize
                        )
                }
                .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                .accessibilityHint("Double tap to \(isPasswordVisible ? "hide" : "show") password")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        errorMessage != nil ? Color.red : (isFocused ? Color.blue : Color.clear),
                        lineWidth: 2
                    )
            )
            // Accessibility for the entire field
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(label) text field")
            .accessibilityValue(text.isEmpty ? "Empty" : "Entered")
            .accessibilityHint(accessibilityHint ?? "")
            .accessibilityIdentifier("securefield.\(label.lowercased().replacingOccurrences(of: " ", with: "."))")

            // Error message
            if let errorMessage = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .accessibilityHidden(true)

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error: \(errorMessage)")
                .onAppear {
                    AccessibilityHelper.announce("Error: \(errorMessage)")
                }
            }
        }
    }

    private func announceVisibilityToggle() {
        AccessibilityHelper.announce(isPasswordVisible ? "Password visible" : "Password hidden")
    }
}

// MARK: - Social Login Button

struct SocialLoginButton: View {

    let provider: SocialProvider
    let action: () -> Void

    enum SocialProvider {
        case google
        case apple
        case facebook

        var icon: String {
            switch self {
            case .google: return "g.circle.fill"
            case .apple: return "apple.logo"
            case .facebook: return "f.circle.fill"
            }
        }

        var name: String {
            switch self {
            case .google: return "Google"
            case .apple: return "Apple"
            case .facebook: return "Facebook"
            }
        }

        var backgroundColor: Color {
            switch self {
            case .google: return .white
            case .apple: return .black
            case .facebook: return Color(red: 66/255, green: 103/255, blue: 178/255)
            }
        }

        var foregroundColor: Color {
            switch self {
            case .google: return .black
            case .apple: return .white
            case .facebook: return .white
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: provider.icon)
                    .font(.system(size: 20))

                Text("Continue with \(provider.name)")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(provider.foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: AccessibilityConstants.minTouchTargetSize + 6)
            .background(provider.backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(.systemGray4), lineWidth: 1)
            )
        }
        .accessibilityLabel("Sign in with \(provider.name)")
        .accessibilityHint("Double tap to authenticate using your \(provider.name) account")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Auth Form Header

struct AuthFormHeader: View {

    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Password Strength Indicator

struct PasswordStrengthIndicator: View {

    let password: String

    private var strength: PasswordStrength {
        if password.isEmpty {
            return .none
        } else if password.count < 6 {
            return .weak
        } else if password.count < 10 && password.rangeOfCharacter(from: .decimalDigits) != nil {
            return .medium
        } else if password.count >= 10 &&
                  password.rangeOfCharacter(from: .decimalDigits) != nil &&
                  password.rangeOfCharacter(from: .uppercaseLetters) != nil &&
                  password.rangeOfCharacter(from: .lowercaseLetters) != nil {
            return .strong
        }
        return .medium
    }

    enum PasswordStrength {
        case none, weak, medium, strong

        var color: Color {
            switch self {
            case .none: return .clear
            case .weak: return .red
            case .medium: return .orange
            case .strong: return .green
            }
        }

        var label: String {
            switch self {
            case .none: return ""
            case .weak: return "Weak"
            case .medium: return "Medium"
            case .strong: return "Strong"
            }
        }

        var progress: CGFloat {
            switch self {
            case .none: return 0
            case .weak: return 0.33
            case .medium: return 0.66
            case .strong: return 1.0
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Rectangle()
                        .fill(index < Int(strength.progress * 3) ? strength.color : Color(.systemGray5))
                        .frame(height: 4)
                        .cornerRadius(2)
                }
            }

            if strength != .none {
                Text("Password strength: \(strength.label)")
                    .font(.caption)
                    .foregroundColor(strength.color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(strength == .none ? "" : "Password strength: \(strength.label)")
        .accessibilityValue(strength.label)
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {

    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(Color(.systemGray6).opacity(0.95))
            .cornerRadius(16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Preview

#if DEBUG
struct LoginViewAccessibility_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Header
            AuthFormHeader(
                title: "Welcome Back",
                subtitle: "Sign in to continue to NovaSocial"
            )

            // Text field
            AccessibleTextField(
                label: "Email",
                placeholder: "Enter your email",
                text: .constant(""),
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                accessibilityHint: "Enter your email address to sign in"
            )

            // Secure field with error
            AccessibleSecureField(
                label: "Password",
                placeholder: "Enter your password",
                text: .constant(""),
                textContentType: .password,
                errorMessage: "Password must be at least 8 characters",
                accessibilityHint: "Enter your password"
            )

            // Password strength
            PasswordStrengthIndicator(password: "MyPassword123")

            // Social login
            VStack(spacing: 12) {
                SocialLoginButton(provider: .google) { }
                SocialLoginButton(provider: .apple) { }
                SocialLoginButton(provider: .facebook) { }
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
