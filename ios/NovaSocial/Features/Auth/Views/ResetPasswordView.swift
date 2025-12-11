import SwiftUI

// MARK: - Reset Password View

/// View for resetting password using a token from email link
/// Typically accessed via deep link: nova://reset-password?token=xxx
struct ResetPasswordView: View {
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
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
    @State private var passwordError: String?
    @State private var confirmPasswordError: String?

    // MARK: - Focus State
    @FocusState private var focusedField: Field?

    enum Field {
        case password
        case confirmPassword
    }

    var body: some View {
        ZStack {
            // Background Image
            Image("Registration-background")
                .resizable()
                .scaledToFill()
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .clipped()
                .ignoresSafeArea(.all)

            // Dark overlay
            Color.black
                .opacity(0.4)
                .ignoresSafeArea()

            // Main Content
            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        let contentVerticalOffset: CGFloat = 120

                        VStack(spacing: 0) {
                            Spacer()
                                .frame(height: 60)

                            // Logo Section
                            logoSection

                            Spacer()
                                .frame(height: 40)

                            // Title
                            Text(LocalizedStringKey("Reset_Password_Title"))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Spacer()
                                .frame(height: 16)

                            // Description
                            Text(LocalizedStringKey("Reset_Password_Description"))
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Spacer()
                                .frame(height: 36)

                            // Password Input Fields
                            VStack(spacing: 16) {
                                passwordTextField
                                confirmPasswordTextField
                            }
                            .padding(.horizontal, 16)

                            // Error Message
                            if let errorMessage = errorMessage {
                                Text(LocalizedStringKey(errorMessage))
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                    .padding(.top, 12)
                            }

                            // Success Message
                            if let successMessage = successMessage {
                                VStack(spacing: 16) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.green)

                                    Text(LocalizedStringKey(successMessage))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.green)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)

                                    // Back to Login button after success
                                    Button(action: {
                                        dismiss()
                                    }) {
                                        Text(LocalizedStringKey("Back_To_Login"))
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.black)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 46)
                                            .background(Color.white)
                                            .cornerRadius(31.50)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 16)
                                }
                                .padding(.top, 24)
                            }

                            if successMessage == nil {
                                Spacer()
                                    .frame(height: 32)

                                // Submit Button
                                submitButton
                                    .padding(.horizontal, 16)
                            }
                        }
                        .offset(y: contentVerticalOffset)

                        Spacer()
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .ignoresSafeArea(.keyboard)
        .navigationBarHidden(true)
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
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
                    .frame(height: 49)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(passwordError != nil ? Color.red : Color.white.opacity(0.3), lineWidth: passwordError != nil ? 1 : 0.5)
                    )

                HStack {
                    if showPassword {
                        TextField("", text: $newPassword, prompt: Text(LocalizedStringKey("New_Password")).foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77)))
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .light))
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .password)
                    } else {
                        SecureField("", text: $newPassword, prompt: Text(LocalizedStringKey("New_Password")).foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77)))
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .light))
                            .focused($focusedField, equals: .password)
                    }

                    Button(action: {
                        showPassword.toggle()
                    }) {
                        Text(showPassword ? "HIDE" : "SHOW")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                    }
                }
                .padding(.horizontal, 16)
            }

            if let error = passwordError {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                    .padding(.leading, 4)
            }
        }
        .onChange(of: newPassword) { _, _ in
            validatePasswordsRealtime()
        }
    }

    // MARK: - Confirm Password TextField
    private var confirmPasswordTextField: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
                    .frame(height: 49)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(confirmPasswordError != nil ? Color.red : Color.white.opacity(0.3), lineWidth: confirmPasswordError != nil ? 1 : 0.5)
                    )

                if showPassword {
                    TextField("", text: $confirmPassword, prompt: Text(LocalizedStringKey("Confirm_New_Password")).foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77)))
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .light))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .focused($focusedField, equals: .confirmPassword)
                } else {
                    SecureField("", text: $confirmPassword, prompt: Text(LocalizedStringKey("Confirm_New_Password")).foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77)))
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .light))
                        .padding(.horizontal, 16)
                        .focused($focusedField, equals: .confirmPassword)
                }
            }

            if let error = confirmPasswordError {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                    .padding(.leading, 4)
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
            .frame(height: 46)
            .background(Color.white)
            .cornerRadius(31.50)
        }
        .disabled(isLoading)
        .accessibilityIdentifier("resetPasswordButton")
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

// MARK: - Preview

#Preview {
    ResetPasswordView(resetToken: "test_token")
        .environmentObject(AuthenticationManager.shared)
}
