import SwiftUI

// MARK: - Reset Password View

/// View for resetting password using a token from email link
/// Typically accessed via deep link: nova://reset-password?token=xxx
struct ResetPasswordView: View {
    // MARK: - Design Constants
    private enum Layout {
        static let contentOffset: CGFloat = 120
        static let inputFieldHeight: CGFloat = 49
        static let buttonHeight: CGFloat = 46
        static let buttonCornerRadius: CGFloat = 31.5
        static let fieldCornerRadius: CGFloat = 6
        static let fieldSpacing: CGFloat = 28
        static let errorOffset: CGFloat = 32
    }

    private enum Colors {
        static let placeholder = Color(white: 0.77)
        static let secondaryText = Color(white: 0.53)
        static let errorText = Color(red: 1, green: 0.4, blue: 0.4)
        static let fieldBorder = Color.white.opacity(0.3)
    }

    // MARK: - Binding
    @Binding var currentPage: AppPage

    // MARK: - Environment
    @EnvironmentObject private var authManager: AuthenticationManager

    // MARK: - Properties
    let resetToken: String

    // MARK: - State
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var passwordError: String?
    @State private var confirmPasswordError: String?

    // MARK: - Focus State
    @FocusState private var focusedField: Field?

    private enum Field {
        case password
        case confirmPassword
    }

    var body: some View {
        ZStack {
            // Background
            backgroundView

            // Main Content
            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Spacer().frame(height: 60)
                            logoSection
                            Spacer().frame(height: 40)

                            // Title
                            Text(LocalizedStringKey("Reset_Password_Title"))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Spacer().frame(height: 16)

                            // Description
                            Text(LocalizedStringKey("Reset_Password_Description"))
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(Colors.placeholder)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Spacer().frame(height: 36)

                            // Password Input Fields
                            VStack(spacing: Layout.fieldSpacing) {
                                passwordTextField
                                confirmPasswordTextField
                            }
                            .padding(.horizontal, 16)

                            // Error Message
                            errorMessageView

                            // Success Message
                            if let successMessage = successMessage {
                                successView(message: successMessage)
                            }

                            if successMessage == nil {
                                Spacer().frame(height: 12)
                                submitButton.padding(.horizontal, 16)
                                Spacer().frame(height: 16)
                                backToLoginButton
                            }
                        }
                        .offset(y: Layout.contentOffset)

                        Spacer()
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Background View
    private var backgroundView: some View {
        ZStack {
            Image("Registration-background")
                .resizable()
                .scaledToFill()
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .clipped()
                .ignoresSafeArea(.all)

            Color.black.opacity(0.4).ignoresSafeArea()
        }
    }

    // MARK: - Error Message View
    private var errorMessageView: some View {
        Text(errorMessage ?? " ")
            .font(.system(size: 12))
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .frame(minHeight: 36)
            .opacity(errorMessage != nil ? 1 : 0)
            .padding(.top, 12)
    }

    // MARK: - Success View
    private func successView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)

            Text(LocalizedStringKey(message))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { currentPage = .login }) {
                Text(LocalizedStringKey("Back_To_Login"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.buttonHeight)
                    .background(Color.white)
                    .cornerRadius(Layout.buttonCornerRadius)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .padding(.top, 24)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Logo Section
    private var logoSection: some View {
        VStack(spacing: 4) {
            Image("Logo-R")
                .resizable()
                .scaledToFit()
                .frame(height: 80)
                .colorInvert()
                .brightness(1)
        }
    }

    // MARK: - Password TextField
    private var passwordTextField: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Layout.fieldCornerRadius)
                .fill(Color.clear)
                .frame(height: Layout.inputFieldHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.fieldCornerRadius)
                        .stroke(passwordError != nil ? Color.red : Colors.fieldBorder, lineWidth: passwordError != nil ? 1 : 0.5)
                )

            HStack {
                if showPassword {
                    TextField("", text: $newPassword, prompt: Text(LocalizedStringKey("New_Password")).foregroundColor(Colors.placeholder))
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .light))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .password)
                } else {
                    SecureField("", text: $newPassword, prompt: Text(LocalizedStringKey("New_Password")).foregroundColor(Colors.placeholder))
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .light))
                        .focused($focusedField, equals: .password)
                }

                Button(action: {
                    showPassword.toggle()
                }) {
                    Text(showPassword ? "HIDE" : "SHOW")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(Colors.secondaryText)
                }
            }
            .padding(.horizontal, 16)

            if let error = passwordError {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 11))
                    .foregroundColor(Colors.errorText)
                    .padding(.leading, 4)
                    .offset(y: Layout.errorOffset)
            }
        }
        .onChange(of: newPassword) { _, _ in
            validatePasswordsRealtime()
        }
    }

    // MARK: - Confirm Password TextField
    private var confirmPasswordTextField: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Layout.fieldCornerRadius)
                .fill(Color.clear)
                .frame(height: Layout.inputFieldHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.fieldCornerRadius)
                        .stroke(confirmPasswordError != nil ? Color.red : Colors.fieldBorder, lineWidth: confirmPasswordError != nil ? 1 : 0.5)
                )

            HStack {
                if showConfirmPassword {
                    TextField("", text: $confirmPassword, prompt: Text(LocalizedStringKey("Confirm_New_Password")).foregroundColor(Colors.placeholder))
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .light))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .confirmPassword)
                } else {
                    SecureField("", text: $confirmPassword, prompt: Text(LocalizedStringKey("Confirm_New_Password")).foregroundColor(Colors.placeholder))
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .light))
                        .focused($focusedField, equals: .confirmPassword)
                }

                Button(action: {
                    showConfirmPassword.toggle()
                }) {
                    Text(showConfirmPassword ? "HIDE" : "SHOW")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(Colors.secondaryText)
                }
            }
            .padding(.horizontal, 16)

            if let error = confirmPasswordError {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 11))
                    .foregroundColor(Colors.errorText)
                    .padding(.leading, 4)
                    .offset(y: Layout.errorOffset)
            }
        }
        .onChange(of: confirmPassword) { _, _ in
            validatePasswordsRealtime()
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        Button(action: {
            Task {
                await handleSubmit()
            }
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.9)
                }
                Text(LocalizedStringKey("Reset_Password"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.buttonHeight)
            .background(Color.white)
            .cornerRadius(Layout.buttonCornerRadius)
        }
        .disabled(isLoading)
        .accessibilityIdentifier("resetPasswordButton")
    }

    // MARK: - Back to Login Button
    private var backToLoginButton: some View {
        Button(action: {
            currentPage = .login
        }) {
            Text(LocalizedStringKey("Back_To_Login"))
                .font(.system(size: 12, weight: .medium))
                .underline()
                .foregroundColor(.white)
        }
    }

    // MARK: - Actions

    private func handleSubmit() async {
        guard validatePasswords() else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await authManager.resetPassword(token: resetToken, newPassword: newPassword)
            successMessage = "Password_Reset_Success"
        } catch {
            let errorDesc = error.localizedDescription.lowercased()
            if errorDesc.contains("invalid") || errorDesc.contains("expired") {
                errorMessage = "Invalid_Reset_Token"
            } else {
                errorMessage = "Password reset failed. Please try again."
            }

            #if DEBUG
            print("[ResetPasswordView] Reset error: \(error)")
            #endif
        }

        isLoading = false
    }

    // MARK: - Validation

    private func validatePasswords() -> Bool {
        if newPassword.isEmpty {
            errorMessage = "Please_enter_a_password"
            return false
        }

        if newPassword.count < 8 {
            errorMessage = "Password_Too_Short"
            return false
        }

        if newPassword != confirmPassword {
            errorMessage = "Passwords_do_not_match"
            return false
        }

        return true
    }

    private func validatePasswordsRealtime() {
        // Validate password length
        if !newPassword.isEmpty && newPassword.count < 8 {
            passwordError = "Password_Too_Short"
        } else {
            passwordError = nil
        }

        // Validate password match
        if !confirmPassword.isEmpty && newPassword != confirmPassword {
            confirmPasswordError = "Passwords_do_not_match"
        } else {
            confirmPasswordError = nil
        }
    }
}

// MARK: - Previews

#Preview("ResetPassword - Default") {
    ResetPasswordView(currentPage: .constant(.resetPassword(token: "test")), resetToken: "test_token")
        .environmentObject(AuthenticationManager.shared)
}

#Preview("ResetPassword - Dark Mode") {
    ResetPasswordView(currentPage: .constant(.resetPassword(token: "test")), resetToken: "test_token")
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
